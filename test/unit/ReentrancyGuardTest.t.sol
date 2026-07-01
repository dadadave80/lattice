// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ReentrancyGuardTestBase} from "@lattice-test/base/ReentrancyGuardTestBase.sol";
import {ReentrancyGuardTestFacet} from "@lattice-test/helpers/ReentrancyGuardTestFacet.sol";
import {IReentrancyGuard} from "@lattice/interfaces/security/IReentrancyGuard.sol";

/// @title ReentrancyGuardTest
/// @notice Exercises the ReentrancyGuard through a REAL {Diamond} (see {ReentrancyGuardTestBase}) — the guard's
///         `_status` lock lives in the diamond's storage and every `this.*` call re-enters the diamond's
///         `delegatecall` fallback, so a genuine reentrant call must revert. This is the whole point of testing
///         the guard on a real diamond rather than a flattened inheritance mock. ReentrancyGuard has no standalone
///         production facet (it is a guard consumed by other facets); the {ReentrancyGuardTestFacet} stands in.
contract ReentrancyGuardTest is ReentrancyGuardTestBase {
    function setUp() public {
        diamond = _deployReentrancyGuard();
        guarded = ReentrancyGuardTestFacet(diamond);
    }

    // -------------------------------------------------------------------------
    // Initial state
    // -------------------------------------------------------------------------

    function test_ERC165RegisteredIReentrancyGuard() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IReentrancyGuard).interfaceId));
    }

    // -------------------------------------------------------------------------
    // Single (non-reentrant) call succeeds
    // -------------------------------------------------------------------------

    function test_SingleCallSucceeds() public {
        guarded.singleCall();
        assertEq(guarded.callCount(), 1);
    }

    function test_MultipleSequentialCallsSucceed() public {
        guarded.singleCall();
        guarded.singleCall();
        guarded.singleCall();
        assertEq(guarded.callCount(), 3);
    }

    // -------------------------------------------------------------------------
    // Reentrant call reverts
    // -------------------------------------------------------------------------

    function test_ReentrantCallReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        guarded.reentrantAttack();
    }

    function test_CrossFunctionReentrancyReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        guarded.callInner();
    }

    // -------------------------------------------------------------------------
    // Lock reset after revert — subsequent calls succeed
    // -------------------------------------------------------------------------

    function test_LockResetAfterRevert() public {
        // reentrantAttack will revert — but singleCall should work fine afterwards
        vm.expectRevert(abi.encodeWithSelector(IReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        guarded.reentrantAttack();

        // The revert in the inner call propagates outward and reverts the whole outer call frame, so `_status`
        // rolls back to _NOT_ENTERED. A new top-level call should therefore succeed.
        guarded.singleCall();
        assertEq(guarded.callCount(), 1);
    }

    // -------------------------------------------------------------------------
    // OZ-reconciliation: RG-1 — reentrancyGuardEntered() view helper
    // -------------------------------------------------------------------------

    /// @notice Verifies that `reentrancyGuardEntered()` returns true while locked and
    /// false both before the guarded call and after it completes.
    /// Equivalent to OZ v5.1.0 `_reentrancyGuardEntered()` parity check.
    function test_ReentrancyGuardEnteredReturnsCorrectState() public {
        // Before: lock is not held — helper should reflect that.
        // We cannot call the internal lib directly, so we observe indirectly:
        // captureEnteredState() writes the mid-call state to enteredSnapshot.
        assertFalse(guarded.enteredSnapshot()); // initial storage value is false (zero default)

        guarded.captureEnteredState();

        // enteredSnapshot was recorded while nonReentrantBefore was active — must be true.
        assertTrue(guarded.enteredSnapshot());

        // After the call completes the lock is released. A fresh guarded call should
        // still succeed (i.e., the helper returning true mid-call did not brick the lock).
        guarded.singleCall();
        assertEq(guarded.callCount(), 1);
    }
}
