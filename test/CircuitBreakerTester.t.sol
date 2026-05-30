// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {ICircuitBreaker} from "@lattice/interfaces/ICircuitBreaker.sol";
import {CircuitBreaker} from "@lattice/security/CircuitBreaker.sol";
import {CircuitBreakerLib} from "@lattice/security/libraries/CircuitBreakerLib.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockCircuitBreakerContract
/// @notice Test double combining CircuitBreaker + AccessControl.
contract MockCircuitBreakerContract is CircuitBreaker, AccessControl {
    /// @notice Initializes both AccessControl and CircuitBreaker modules.
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        CircuitBreakerLib.__CircuitBreaker_init();
        InitializableLib.postInitializer(s);
    }

    /// @notice External gate that reverts when the circuit for `key` is tripped.
    function gatedAction(bytes32 key) external view {
        CircuitBreakerLib.checkNotTripped(key);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title CircuitBreakerTester
/// @notice Comprehensive tests for the CircuitBreaker module.
contract CircuitBreakerTester is Test {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 private constant KEY_A = keccak256("KEY_A");
    bytes32 private constant KEY_B = keccak256("KEY_B");

    MockCircuitBreakerContract internal mock;
    address internal admin = address(0xA1);
    address internal nonAdmin = address(0xB2);

    function setUp() public {
        mock = new MockCircuitBreakerContract();
        mock.initialize(admin);
    }

    // -------------------------------------------------------------------------
    // ERC-165
    // -------------------------------------------------------------------------

    function test_ERC165RegisteredICircuitBreaker() public view {
        assertTrue(mock.supportsInterface(type(ICircuitBreaker).interfaceId));
    }

    // -------------------------------------------------------------------------
    // setThreshold — access control
    // -------------------------------------------------------------------------

    function test_SetThresholdByNonAdminReverts() public {
        vm.prank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, DEFAULT_ADMIN_ROLE
            )
        );
        mock.setThreshold(KEY_A, 100, 3600);
    }

    // -------------------------------------------------------------------------
    // setThreshold — invalid window
    // -------------------------------------------------------------------------

    function test_SetThresholdWithZeroWindowReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ICircuitBreaker.CircuitBreakerInvalidWindow.selector));
        mock.setThreshold(KEY_A, 100, 0);
    }

    // -------------------------------------------------------------------------
    // setThreshold — happy path
    // -------------------------------------------------------------------------

    function test_SetThresholdStoresValues() public {
        vm.prank(admin);
        mock.setThreshold(KEY_A, 500, 1800);

        (uint256 t, uint48 w) = mock.getThreshold(KEY_A);
        assertEq(t, 500);
        assertEq(w, 1800);
    }

    function test_SetThresholdEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ICircuitBreaker.CircuitBreakerThresholdSet(KEY_A, 500, 1800);
        mock.setThreshold(KEY_A, 500, 1800);
    }

    function test_SetThresholdResetsCumulativeAndTripped() public {
        // Configure, trip, then reconfigure — state must reset.
        vm.prank(admin);
        mock.setThreshold(KEY_A, 10, 3600);
        vm.prank(admin);
        mock.recordObservation(KEY_A, 10); // trip
        assertTrue(mock.isTripped(KEY_A));

        vm.prank(admin);
        mock.setThreshold(KEY_A, 200, 7200);

        assertFalse(mock.isTripped(KEY_A));
        (uint256 cum,) = mock.getCumulative(KEY_A);
        assertEq(cum, 0);
    }

    // -------------------------------------------------------------------------
    // recordObservation — unconfigured
    // -------------------------------------------------------------------------

    function test_RecordObservationOnUnconfiguredKeyReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ICircuitBreaker.CircuitBreakerNotConfigured.selector, KEY_A));
        mock.recordObservation(KEY_A, 1);
    }

    // -------------------------------------------------------------------------
    // recordObservation — accumulation within window
    // -------------------------------------------------------------------------

    function test_RecordObservationAccumulatesWithinWindow() public {
        vm.prank(admin);
        mock.setThreshold(KEY_A, 1000, 3600);

        vm.prank(admin);
        mock.recordObservation(KEY_A, 100);
        vm.prank(admin);
        mock.recordObservation(KEY_A, 200);

        (uint256 cum,) = mock.getCumulative(KEY_A);
        assertEq(cum, 300);
        assertFalse(mock.isTripped(KEY_A));
    }

    // -------------------------------------------------------------------------
    // recordObservation — tripping at threshold
    // -------------------------------------------------------------------------

    function test_RecordObservationAtThresholdTrips() public {
        vm.prank(admin);
        mock.setThreshold(KEY_A, 100, 3600);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ICircuitBreaker.CircuitBreakerTripped(KEY_A, 100, 100);
        mock.recordObservation(KEY_A, 100);

        assertTrue(mock.isTripped(KEY_A));
    }

    function test_RecordObservationExceedingThresholdTrips() public {
        vm.prank(admin);
        mock.setThreshold(KEY_A, 50, 3600);

        vm.prank(admin);
        mock.recordObservation(KEY_A, 75);

        assertTrue(mock.isTripped(KEY_A));
    }

    // -------------------------------------------------------------------------
    // checkNotTripped
    // -------------------------------------------------------------------------

    function test_CheckNotTrippedSucceedsWhenNotTripped() public view {
        // Should not revert — KEY_A was never configured, but checkNotTripped only reads the
        // tripped flag (which defaults to false).
        mock.gatedAction(KEY_A);
    }

    function test_CheckNotTrippedRevertsWhenTripped() public {
        vm.prank(admin);
        mock.setThreshold(KEY_A, 10, 3600);
        vm.prank(admin);
        mock.recordObservation(KEY_A, 10);

        vm.expectRevert(abi.encodeWithSelector(ICircuitBreaker.CircuitBreakerTrippedError.selector, KEY_A));
        mock.gatedAction(KEY_A);
    }

    // -------------------------------------------------------------------------
    // reset
    // -------------------------------------------------------------------------

    function test_ResetByNonAdminReverts() public {
        vm.prank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, DEFAULT_ADMIN_ROLE
            )
        );
        mock.reset(KEY_A);
    }

    function test_ResetClearsTrippedAndCumulative() public {
        vm.prank(admin);
        mock.setThreshold(KEY_A, 10, 3600);
        vm.prank(admin);
        mock.recordObservation(KEY_A, 10);
        assertTrue(mock.isTripped(KEY_A));

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ICircuitBreaker.CircuitBreakerReset(KEY_A);
        mock.reset(KEY_A);

        assertFalse(mock.isTripped(KEY_A));
        (uint256 cum,) = mock.getCumulative(KEY_A);
        assertEq(cum, 0);
    }

    function test_GatedActionSucceedsAfterReset() public {
        vm.prank(admin);
        mock.setThreshold(KEY_A, 10, 3600);
        vm.prank(admin);
        mock.recordObservation(KEY_A, 10);

        vm.prank(admin);
        mock.reset(KEY_A);

        // Must no longer revert.
        mock.gatedAction(KEY_A);
    }

    // -------------------------------------------------------------------------
    // Window rollover
    // -------------------------------------------------------------------------

    function test_WindowRolloverResetsCumulative() public {
        vm.prank(admin);
        mock.setThreshold(KEY_A, 1000, 3600);

        vm.prank(admin);
        mock.recordObservation(KEY_A, 400);

        // Fast-forward past the window.
        vm.warp(block.timestamp + 3601);

        vm.prank(admin);
        mock.recordObservation(KEY_A, 50);

        // Cumulative should only contain the post-rollover value.
        (uint256 cum,) = mock.getCumulative(KEY_A);
        assertEq(cum, 50);
    }

    function test_WindowRolloverDoesNotTrip() public {
        vm.prank(admin);
        mock.setThreshold(KEY_A, 100, 3600);

        vm.prank(admin);
        mock.recordObservation(KEY_A, 90); // just under threshold

        vm.warp(block.timestamp + 3601);

        // After rollover this should be a fresh 80 — not 90+80=170.
        vm.prank(admin);
        mock.recordObservation(KEY_A, 80);

        assertFalse(mock.isTripped(KEY_A));
    }

    // -------------------------------------------------------------------------
    // Independent keys
    // -------------------------------------------------------------------------

    function test_IndependentKeys() public {
        vm.prank(admin);
        mock.setThreshold(KEY_A, 10, 3600);
        vm.prank(admin);
        mock.setThreshold(KEY_B, 1000, 3600);

        vm.prank(admin);
        mock.recordObservation(KEY_A, 10); // trip KEY_A

        assertTrue(mock.isTripped(KEY_A));
        assertFalse(mock.isTripped(KEY_B)); // KEY_B unaffected
    }

    // -------------------------------------------------------------------------
    // recordObservation access control
    // -------------------------------------------------------------------------

    function test_RecordObservationByNonAdminReverts() public {
        vm.prank(admin);
        mock.setThreshold(KEY_A, 100, 3600);

        vm.prank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, DEFAULT_ADMIN_ROLE
            )
        );
        mock.recordObservation(KEY_A, 50);
    }
}
