// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {ArchiveFork} from "@lattice-test/helpers/ArchiveFork.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IChainlinkCREAdapter} from "@lattice/interfaces/oracles/IChainlinkCREAdapter.sol";
import {ChainlinkCREAdapter} from "@lattice/oracles/chainlink/ChainlinkCREAdapter.sol";
import {ChainlinkCREAdapterLib} from "@lattice/oracles/chainlink/ChainlinkCREAdapterLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Mock diamond combining AccessControl + ChainlinkCREAdapter.
contract MockChainlinkCREForkContract is AccessControl, ChainlinkCREAdapter, Initializable {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(AccessControl, ChainlinkCREAdapter)
        returns (bytes memory)
    {}

    function initialize(address _admin) external initializer {
        AccessControlLib.__AccessControl_init(_admin);
        ChainlinkCREAdapterLib.__ChainlinkCREAdapter_init();
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title ChainlinkCREAdapterFork
/// @notice Fork test wiring the real Chainlink CRE KeystoneForwarder on Ethereum mainnet into the receiver.
///
/// Enabling this test:
///   export MAINNET_RPC_URL=<your-archive-rpc-url>
///   forge test --match-path "test/fork/ChainlinkCREAdapterFork.t.sol"
///
/// Without MAINNET_RPC_URL set, all tests here are skipped. The fork is pinned (CRE_FORK_BLOCK overrides it),
/// so it needs an archive endpoint. The default forwarder is Chainlink's production mainnet KeystoneForwarder;
/// CRE_KEYSTONE_FORWARDER overrides it. The forwarder delivers reports only with valid DON signatures (an
/// off-chain flow), so this test verifies the on-chain configuration surface: the forwarder is stored, a
/// workflow can be allowlisted, and an unauthorised caller is rejected.
contract ChainlinkCREAdapterFork is Test {
    /// @notice Pinned mainnet block (2026), shared with the EntryPoint suites. The KeystoneForwarder was
    ///         deployed in October 2025, so the 21_500_000 pin of the other oracle suites predates it.
    uint256 constant DEFAULT_FORK_BLOCK = 25_000_000;

    /// @notice Production KeystoneForwarder for `ethereum-mainnet` in Chainlink's CRE forwarder directory
    ///         (https://docs.chain.link/cre/guides/workflow/using-evm-client/forwarder-directory-ts).
    address constant KEYSTONE_FORWARDER = 0x0b93082D9b3C7C97fAcd250082899BAcf3af3885;

    bytes32 constant WORKFLOW_ID = keccak256("FORK_WORKFLOW");

    MockChainlinkCREForkContract adapter;
    address forwarder;
    address admin = address(0x1);

    function setUp() public {
        if (bytes(vm.envOr("MAINNET_RPC_URL", string(""))).length == 0) {
            vm.skip(true);
            return;
        }
        forwarder = vm.envOr("CRE_KEYSTONE_FORWARDER", KEYSTONE_FORWARDER);
        if (!ArchiveFork.select("mainnet", vm.envOr("CRE_FORK_BLOCK", DEFAULT_FORK_BLOCK))) return;
        // The pin postdates the forwarder, so missing code means a wrong address or pin: skip locally, fail on
        // the strict weekly lane.
        if (forwarder.code.length == 0) {
            ArchiveFork.skipOrFail(ArchiveFork.strict(), "CRE KeystoneForwarder has no code at the fork block");
            return;
        }

        adapter = new MockChainlinkCREForkContract();
        adapter.initialize(admin);
    }

    /// @notice The default forwarder is a live KeystoneForwarder (`typeAndVersion()` names the contract).
    function test_Fork_DefaultForwarderIsKeystoneForwarder() public view {
        (bool ok, bytes memory ret) = KEYSTONE_FORWARDER.staticcall(abi.encodeWithSignature("typeAndVersion()"));
        assertTrue(ok, "typeAndVersion() reverted");
        assertEq(abi.decode(ret, (string)), "KeystoneForwarder 1.0.0", "not a KeystoneForwarder");
    }

    function test_Fork_ConfigRoundTrips() public {
        vm.startPrank(admin);
        adapter.setForwarder(forwarder);
        adapter.setWorkflow(WORKFLOW_ID, true);
        vm.stopPrank();

        assertEq(adapter.getForwarder(), forwarder, "forwarder mismatch");
        assertTrue(adapter.isWorkflowAllowed(WORKFLOW_ID), "workflow not allowlisted");
    }

    function test_Fork_RejectsNonForwarderCaller() public {
        vm.prank(admin);
        adapter.setForwarder(forwarder);

        bytes memory metadata = abi.encodePacked(WORKFLOW_ID, bytes10("fork"), address(0xABCD), bytes2(0x0001));
        vm.expectRevert(abi.encodeWithSelector(IChainlinkCREAdapter.CREOnlyForwarder.selector, address(this)));
        adapter.onReport(metadata, abi.encode(uint256(1)));
    }
}
