// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IChainlinkCREAdapter} from "@lattice/interfaces/oracles/IChainlinkCREAdapter.sol";
import {ChainlinkCREAdapter} from "@lattice/oracles/chainlink/ChainlinkCREAdapter.sol";
import {ChainlinkCREAdapterLib} from "@lattice/oracles/chainlink/ChainlinkCREAdapterLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Mock diamond combining AccessControl + ChainlinkCREAdapter.
contract MockChainlinkCREForkContract is AccessControl, ChainlinkCREAdapter {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(AccessControl, ChainlinkCREAdapter)
        returns (bytes memory)
    {}

    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        s = InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        ChainlinkCREAdapterLib.__ChainlinkCREAdapter_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title ChainlinkCREAdapterFork
/// @notice Fork test wiring a real Chainlink CRE KeystoneForwarder into the receiver.
///
/// Enabling this test:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   export CRE_KEYSTONE_FORWARDER=<KeystoneForwarder address for the forked chain>
///   forge test --match-path "test/fork/ChainlinkCREAdapterFork.t.sol"
///
/// The KeystoneForwarder delivers reports only with valid DON signatures (an off-chain flow), so this
/// test verifies the on-chain configuration surface: the forwarder is stored, a workflow can be
/// allowlisted, and an unauthorised caller is rejected. It is skipped unless both MAINNET_RPC_URL and
/// CRE_KEYSTONE_FORWARDER are set.
contract ChainlinkCREAdapterFork is Test {
    uint256 constant DEFAULT_FORK_BLOCK = 21_500_000;

    bytes32 constant WORKFLOW_ID = keccak256("FORK_WORKFLOW");

    MockChainlinkCREForkContract adapter;
    address forwarder;
    address admin = address(0x1);

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        forwarder = vm.envOr("CRE_KEYSTONE_FORWARDER", address(0));
        if (bytes(rpc).length == 0 || forwarder == address(0)) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", vm.envOr("CRE_FORK_BLOCK", DEFAULT_FORK_BLOCK));

        adapter = new MockChainlinkCREForkContract();
        adapter.initialize(admin);
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
