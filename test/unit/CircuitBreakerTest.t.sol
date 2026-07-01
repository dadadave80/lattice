// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {CircuitBreakerTestBase} from "@lattice-test/base/CircuitBreakerTestBase.sol";
import {CircuitBreakerTestFacet} from "@lattice-test/helpers/CircuitBreakerTestFacet.sol";
import {DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {ICircuitBreaker} from "@lattice/interfaces/security/ICircuitBreaker.sol";
import {CircuitBreaker} from "@lattice/security/CircuitBreaker.sol";

/// @title CircuitBreakerTest
/// @notice Exercises the CircuitBreaker facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployCircuitBreaker} script (see {CircuitBreakerTestBase}) — every call below routes through the
///         diamond's `delegatecall` dispatch, not a flattened inheritance mock. Admin gating is enforced by the
///         cut-in `AccessControl` facet; `supportsInterface` by the cut-in `ERC165Facet`; the `checkNotTripped`
///         consumer guard by the appended test-only {CircuitBreakerTestFacet}.
contract CircuitBreakerTest is CircuitBreakerTestBase {
    bytes32 private constant KEY_A = keccak256("KEY_A");
    bytes32 private constant KEY_B = keccak256("KEY_B");

    address internal admin = address(0xA1);
    address internal nonAdmin = address(0xB2);

    function setUp() public {
        diamond = _deployCircuitBreaker(admin);
        breaker = CircuitBreaker(diamond);
        guard = CircuitBreakerTestFacet(diamond);
    }

    // -------------------------------------------------------------------------
    // ERC-165
    // -------------------------------------------------------------------------

    function test_ERC165RegisteredICircuitBreaker() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(ICircuitBreaker).interfaceId));
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
        breaker.setThreshold(KEY_A, 100, 3600);
    }

    // -------------------------------------------------------------------------
    // setThreshold — invalid threshold / invalid window
    // -------------------------------------------------------------------------

    function test_SetThresholdZeroReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ICircuitBreaker.CircuitBreakerInvalidThreshold.selector));
        breaker.setThreshold(KEY_A, 0, 3600);
    }

    function test_SetThresholdWithZeroWindowReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ICircuitBreaker.CircuitBreakerInvalidWindow.selector));
        breaker.setThreshold(KEY_A, 100, 0);
    }

    // -------------------------------------------------------------------------
    // setThreshold — happy path
    // -------------------------------------------------------------------------

    function test_SetThresholdStoresValues() public {
        vm.prank(admin);
        breaker.setThreshold(KEY_A, 500, 1800);

        (uint256 t, uint48 w) = breaker.getThreshold(KEY_A);
        assertEq(t, 500);
        assertEq(w, 1800);
    }

    function test_SetThresholdEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ICircuitBreaker.CircuitBreakerThresholdSet(KEY_A, 500, 1800);
        breaker.setThreshold(KEY_A, 500, 1800);
    }

    function test_SetThresholdResetsCumulativeAndTripped() public {
        // Configure, trip, then reconfigure — state must reset.
        vm.prank(admin);
        breaker.setThreshold(KEY_A, 10, 3600);
        vm.prank(admin);
        breaker.recordObservation(KEY_A, 10); // trip
        assertTrue(breaker.isTripped(KEY_A));

        vm.prank(admin);
        breaker.setThreshold(KEY_A, 200, 7200);

        assertFalse(breaker.isTripped(KEY_A));
        (uint256 cum,) = breaker.getCumulative(KEY_A);
        assertEq(cum, 0);
    }

    // -------------------------------------------------------------------------
    // recordObservation — unconfigured
    // -------------------------------------------------------------------------

    function test_RecordObservationOnUnconfiguredKeyReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ICircuitBreaker.CircuitBreakerNotConfigured.selector, KEY_A));
        breaker.recordObservation(KEY_A, 1);
    }

    // -------------------------------------------------------------------------
    // recordObservation — accumulation within window
    // -------------------------------------------------------------------------

    function test_RecordObservationAccumulatesWithinWindow() public {
        vm.prank(admin);
        breaker.setThreshold(KEY_A, 1000, 3600);

        vm.prank(admin);
        breaker.recordObservation(KEY_A, 100);
        vm.prank(admin);
        breaker.recordObservation(KEY_A, 200);

        (uint256 cum,) = breaker.getCumulative(KEY_A);
        assertEq(cum, 300);
        assertFalse(breaker.isTripped(KEY_A));
    }

    // -------------------------------------------------------------------------
    // recordObservation — tripping at threshold
    // -------------------------------------------------------------------------

    function test_RecordObservationAtThresholdTrips() public {
        vm.prank(admin);
        breaker.setThreshold(KEY_A, 100, 3600);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ICircuitBreaker.CircuitBreakerTripped(KEY_A, 100, 100);
        breaker.recordObservation(KEY_A, 100);

        assertTrue(breaker.isTripped(KEY_A));
    }

    function test_RecordObservationExceedingThresholdTrips() public {
        vm.prank(admin);
        breaker.setThreshold(KEY_A, 50, 3600);

        vm.prank(admin);
        breaker.recordObservation(KEY_A, 75);

        assertTrue(breaker.isTripped(KEY_A));
    }

    // -------------------------------------------------------------------------
    // checkNotTripped
    // -------------------------------------------------------------------------

    function test_CheckNotTrippedSucceedsWhenNotTripped() public view {
        // Should not revert — KEY_A was never configured, but checkNotTripped only reads the
        // tripped flag (which defaults to false).
        guard.gatedAction(KEY_A);
    }

    function test_CheckNotTrippedRevertsWhenTripped() public {
        vm.prank(admin);
        breaker.setThreshold(KEY_A, 10, 3600);
        vm.prank(admin);
        breaker.recordObservation(KEY_A, 10);

        vm.expectRevert(abi.encodeWithSelector(ICircuitBreaker.CircuitBreakerTrippedError.selector, KEY_A));
        guard.gatedAction(KEY_A);
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
        breaker.reset(KEY_A);
    }

    function test_ResetClearsTrippedAndCumulative() public {
        vm.prank(admin);
        breaker.setThreshold(KEY_A, 10, 3600);
        vm.prank(admin);
        breaker.recordObservation(KEY_A, 10);
        assertTrue(breaker.isTripped(KEY_A));

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ICircuitBreaker.CircuitBreakerReset(KEY_A);
        breaker.reset(KEY_A);

        assertFalse(breaker.isTripped(KEY_A));
        (uint256 cum,) = breaker.getCumulative(KEY_A);
        assertEq(cum, 0);
    }

    function test_GatedActionSucceedsAfterReset() public {
        vm.prank(admin);
        breaker.setThreshold(KEY_A, 10, 3600);
        vm.prank(admin);
        breaker.recordObservation(KEY_A, 10);

        vm.prank(admin);
        breaker.reset(KEY_A);

        // Must no longer revert.
        guard.gatedAction(KEY_A);
    }

    // -------------------------------------------------------------------------
    // Window rollover
    // -------------------------------------------------------------------------

    function test_WindowRolloverResetsCumulative() public {
        vm.prank(admin);
        breaker.setThreshold(KEY_A, 1000, 3600);

        vm.prank(admin);
        breaker.recordObservation(KEY_A, 400);

        // Fast-forward past the window.
        vm.warp(block.timestamp + 3601);

        vm.prank(admin);
        breaker.recordObservation(KEY_A, 50);

        // Cumulative should only contain the post-rollover value.
        (uint256 cum,) = breaker.getCumulative(KEY_A);
        assertEq(cum, 50);
    }

    function test_WindowRolloverDoesNotTrip() public {
        vm.prank(admin);
        breaker.setThreshold(KEY_A, 100, 3600);

        vm.prank(admin);
        breaker.recordObservation(KEY_A, 90); // just under threshold

        vm.warp(block.timestamp + 3601);

        // After rollover this should be a fresh 80 — not 90+80=170.
        vm.prank(admin);
        breaker.recordObservation(KEY_A, 80);

        assertFalse(breaker.isTripped(KEY_A));
    }

    // -------------------------------------------------------------------------
    // Independent keys
    // -------------------------------------------------------------------------

    function test_IndependentKeys() public {
        vm.prank(admin);
        breaker.setThreshold(KEY_A, 10, 3600);
        vm.prank(admin);
        breaker.setThreshold(KEY_B, 1000, 3600);

        vm.prank(admin);
        breaker.recordObservation(KEY_A, 10); // trip KEY_A

        assertTrue(breaker.isTripped(KEY_A));
        assertFalse(breaker.isTripped(KEY_B)); // KEY_B unaffected
    }

    // -------------------------------------------------------------------------
    // recordObservation — exact threshold boundary
    // -------------------------------------------------------------------------

    function test_RecordObservationAtExactThresholdTrips() public {
        // cumulative == threshold should trip (>= check).
        vm.prank(admin);
        breaker.setThreshold(KEY_A, 100, 3600);

        vm.prank(admin);
        breaker.recordObservation(KEY_A, 99); // one below — must not trip
        assertFalse(breaker.isTripped(KEY_A));

        vm.prank(admin);
        breaker.recordObservation(KEY_A, 1); // cumulative == threshold → trips
        assertTrue(breaker.isTripped(KEY_A));
    }

    function test_RecordObservationOneBelowThresholdDoesNotTrip() public {
        vm.prank(admin);
        breaker.setThreshold(KEY_A, 100, 3600);

        vm.prank(admin);
        breaker.recordObservation(KEY_A, 99);
        assertFalse(breaker.isTripped(KEY_A));

        (uint256 cum,) = breaker.getCumulative(KEY_A);
        assertEq(cum, 99);
    }

    // -------------------------------------------------------------------------
    // recordObservation — already-tripped circuit reverts
    // -------------------------------------------------------------------------

    function test_RecordObservationOnTrippedCircuitReverts() public {
        vm.prank(admin);
        breaker.setThreshold(KEY_A, 10, 3600);
        vm.prank(admin);
        breaker.recordObservation(KEY_A, 10); // trip
        assertTrue(breaker.isTripped(KEY_A));

        // Subsequent observation must revert, not silently accumulate.
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ICircuitBreaker.CircuitBreakerTrippedError.selector, KEY_A));
        breaker.recordObservation(KEY_A, 1);
    }

    function test_RecordObservationAfterResetSucceeds() public {
        vm.prank(admin);
        breaker.setThreshold(KEY_A, 10, 3600);
        vm.prank(admin);
        breaker.recordObservation(KEY_A, 10); // trip

        vm.prank(admin);
        breaker.reset(KEY_A); // clear

        // Must succeed after reset.
        vm.prank(admin);
        breaker.recordObservation(KEY_A, 5);
        assertFalse(breaker.isTripped(KEY_A));
    }

    // -------------------------------------------------------------------------
    // recordObservation — window rollover edge
    // -------------------------------------------------------------------------

    function test_WindowRolloverAtExactBoundaryResetsCumulative() public {
        vm.prank(admin);
        breaker.setThreshold(KEY_A, 1000, 3600);

        vm.prank(admin);
        breaker.recordObservation(KEY_A, 500);

        // Warp to exactly the window boundary (windowStart + windowSeconds).
        vm.warp(block.timestamp + 3600);

        vm.prank(admin);
        breaker.recordObservation(KEY_A, 1);

        // Cumulative should be the fresh value only (window rolled).
        (uint256 cum,) = breaker.getCumulative(KEY_A);
        assertEq(cum, 1);
    }

    // -------------------------------------------------------------------------
    // reset — unconfigured key
    // -------------------------------------------------------------------------

    function test_ResetOnUnconfiguredKeyReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ICircuitBreaker.CircuitBreakerNotConfigured.selector, KEY_A));
        breaker.reset(KEY_A);
    }

    // -------------------------------------------------------------------------
    // recordObservation access control
    // -------------------------------------------------------------------------

    function test_RecordObservationByNonAdminReverts() public {
        vm.prank(admin);
        breaker.setThreshold(KEY_A, 100, 3600);

        vm.prank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, DEFAULT_ADMIN_ROLE
            )
        );
        breaker.recordObservation(KEY_A, 50);
    }
}
