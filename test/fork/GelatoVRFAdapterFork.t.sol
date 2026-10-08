// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {GelatoVRFAdapter} from "@lattice/oracles/gelato/GelatoVRFAdapter.sol";
import {GelatoVRFAdapterLib} from "@lattice/oracles/gelato/GelatoVRFAdapterLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCK CONTRACT
// ---------------------------------------------------------------------------

/// @notice Mock Diamond that combines AccessControl + GelatoVRFAdapter, matching
///         the pattern from GelatoVRFAdapterTest.t.sol.
contract MockGelatoVRFAdapterForkContract is AccessControl, GelatoVRFAdapter, Initializable {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(AccessControl, GelatoVRFAdapter) returns (bytes memory) {}

    function initialize(address _admin) external initializer {
        AccessControlLib.__AccessControl_init(_admin);
        GelatoVRFAdapterLib.__GelatoVRFAdapter_init();
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

// ---------------------------------------------------------------------------
//                              FORK TESTS
// ---------------------------------------------------------------------------

/// @title GelatoVRFAdapterFork
/// @notice Fork tests that exercise GelatoVRFAdapter operator configuration
///         against a live Gelato VRF dedicated operator on Ethereum mainnet.
///
/// Enabling fork tests:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   forge test --match-path "test/fork/GelatoVRFAdapterFork.t.sol"
///
/// Without MAINNET_RPC_URL set, all tests in this contract are skipped. The
/// operator is the consumer's Gelato dedicated msg.sender, so there is no single
/// mainnet address: by default the test derives the admin's one from Gelato's
/// live OpsProxyFactory at the pinned block. GELATO_VRF_OPERATOR overrides it.
/// The live operator/round flow is off-chain, so this only verifies the
/// on-chain configuration round-trip.
contract GelatoVRFAdapterFork is Test {
    // -------------------------------------------------------------------------
    //                         Mainnet pin
    // -------------------------------------------------------------------------

    /// @notice Pinned mainnet block for deterministic results (December 2024).
    uint256 constant FORK_BLOCK = 21_500_000;

    /// @notice Gelato's OpsProxyFactory on Ethereum mainnet: Automate
    ///         (0x2A6C106ae13B558BB9E2Ec64Bd2f1f7BEFF3A5E0) → `taskModuleAddresses(PROXY)` → `opsProxyFactory()`.
    address constant OPS_PROXY_FACTORY = 0x44bde1bccdD06119262f1fE441FBe7341EaaC185;

    // -------------------------------------------------------------------------
    //                              State
    // -------------------------------------------------------------------------

    MockGelatoVRFAdapterForkContract adapter;
    address admin = address(0x1);
    address operator;

    // -------------------------------------------------------------------------
    //                              Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        if (bytes(vm.envOr("MAINNET_RPC_URL", string(""))).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", FORK_BLOCK);
        operator = vm.envOr("GELATO_VRF_OPERATOR", _dedicatedMsgSender(admin));

        adapter = new MockGelatoVRFAdapterForkContract();
        adapter.initialize(admin);
    }

    // -------------------------------------------------------------------------
    //                              Tests
    // -------------------------------------------------------------------------

    /// @notice Configure the live dedicated operator and verify the round-trip.
    function test_Fork_SetOperatorRoundTrips() public {
        vm.prank(admin);
        adapter.setOperator(operator);

        assertEq(adapter.getOperator(), operator, "operator mismatch");
    }

    /// @dev `owner`'s Gelato dedicated msg.sender, read from the live OpsProxyFactory (`getProxyOf` returns the
    ///      CREATE2 proxy address whether or not it is deployed yet).
    function _dedicatedMsgSender(address owner) internal view returns (address proxy) {
        (bool ok, bytes memory ret) =
            OPS_PROXY_FACTORY.staticcall(abi.encodeWithSignature("getProxyOf(address)", owner));
        assertTrue(ok, "getProxyOf reverted");
        (proxy,) = abi.decode(ret, (address, bool));
        assertTrue(proxy != address(0), "factory returned no proxy");
    }
}
