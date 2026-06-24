// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {GelatoVRFAdapter} from "@lattice/oracles/GelatoVRFAdapter.sol";
import {GelatoVRFAdapterLib} from "@lattice/oracles/libraries/GelatoVRFAdapterLib.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCK CONTRACT
// ---------------------------------------------------------------------------

/// @notice Mock Diamond that combines AccessControl + GelatoVRFAdapter, matching
///         the pattern from GelatoVRFAdapterTester.t.sol.
contract MockGelatoVRFAdapterForkContract is AccessControl, GelatoVRFAdapter {
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        GelatoVRFAdapterLib.__GelatoVRFAdapter_init();
        InitializableLib.postInitializer(s);
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
///   export GELATO_VRF_OPERATOR=<dedicated-operator-address>
///   forge test --match-path "test/fork/*"
///
/// Without GELATO_VRF_OPERATOR set, all tests in this contract are skipped.
/// The live operator/round flow is off-chain, so this only verifies the
/// on-chain configuration round-trip.
contract GelatoVRFAdapterFork is Test {
    // -------------------------------------------------------------------------
    //                         Mainnet pin
    // -------------------------------------------------------------------------

    /// @notice Pinned mainnet block for deterministic results (December 2024).
    uint256 constant FORK_BLOCK = 21_500_000;

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
        operator = vm.envOr("GELATO_VRF_OPERATOR", address(0));
        if (operator == address(0)) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", FORK_BLOCK);

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
}
