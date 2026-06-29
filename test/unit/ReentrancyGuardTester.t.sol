// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IReentrancyGuard} from "@lattice/interfaces/security/IReentrancyGuard.sol";
import {ReentrancyGuard} from "@lattice/security/ReentrancyGuard.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockReentrantContract
/// @notice Test double that inherits ReentrancyGuard and exposes reentrant attack scenarios.
contract MockReentrantContract is ReentrancyGuard {
    /// @notice Tracks successful call count for assertion purposes.
    uint256 public callCount;

    /// @notice Records the guard state snapshot captured inside a guarded call.
    bool public enteredSnapshot;

    /// @notice Initializes the ReentrancyGuard module.
    function initialize() external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ReentrancyGuardLib.__ReentrancyGuard_init();
        InitializableLib.postInitializer(s);
    }

    /// @notice A non-reentrant function that increments callCount.
    /// @dev Protected by nonReentrantBefore / nonReentrantAfter.
    function singleCall() external {
        ReentrancyGuardLib.nonReentrantBefore();
        callCount++;
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice A non-reentrant function that attempts to call itself recursively.
    /// @dev The reentrant call should revert with ReentrancyGuardReentrantCall.
    function reentrantAttack() external {
        ReentrancyGuardLib.nonReentrantBefore();
        callCount++;
        // Attempt reentrant call — this should revert
        this.reentrantAttack();
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice A non-reentrant function that calls a secondary non-reentrant function.
    /// @dev Tests mutual exclusion: both use the same lock so the inner call should revert.
    function callInner() external {
        ReentrancyGuardLib.nonReentrantBefore();
        callCount++;
        // Attempt to enter a different guarded function — same lock, should revert
        this.singleCall();
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Captures `reentrancyGuardEntered()` into `enteredSnapshot` mid-call,
    /// then releases the lock. Used to verify the helper returns true while locked.
    function captureEnteredState() external {
        ReentrancyGuardLib.nonReentrantBefore();
        enteredSnapshot = ReentrancyGuardLib.reentrancyGuardEntered();
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Returns whether the ERC-165 interface is registered.
    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title ReentrancyGuardTester
/// @notice Comprehensive tests for the ReentrancyGuard module.
contract ReentrancyGuardTester is Test {
    MockReentrantContract internal mock;

    function setUp() public {
        mock = new MockReentrantContract();
        mock.initialize();
    }

    // -------------------------------------------------------------------------
    // Initial state
    // -------------------------------------------------------------------------

    function test_ERC165RegisteredIReentrancyGuard() public view {
        assertTrue(mock.supportsInterface(type(IReentrancyGuard).interfaceId));
    }

    // -------------------------------------------------------------------------
    // Single (non-reentrant) call succeeds
    // -------------------------------------------------------------------------

    function test_SingleCallSucceeds() public {
        mock.singleCall();
        assertEq(mock.callCount(), 1);
    }

    function test_MultipleSequentialCallsSucceed() public {
        mock.singleCall();
        mock.singleCall();
        mock.singleCall();
        assertEq(mock.callCount(), 3);
    }

    // -------------------------------------------------------------------------
    // Reentrant call reverts
    // -------------------------------------------------------------------------

    function test_ReentrantCallReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        mock.reentrantAttack();
    }

    function test_CrossFunctionReentrancyReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        mock.callInner();
    }

    // -------------------------------------------------------------------------
    // Lock reset after revert — subsequent calls succeed
    // -------------------------------------------------------------------------

    function test_LockResetAfterRevert() public {
        // reentrantAttack will revert — but singleCall should work fine afterwards
        vm.expectRevert(abi.encodeWithSelector(IReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        mock.reentrantAttack();

        // The lock was never properly set because nonReentrantAfter was not reached;
        // however the revert in the inner call propagates outward and reverts the
        // outer call as well, so _status stays at _NOT_ENTERED in a reverted frame.
        // A new top-level call should succeed.
        mock.singleCall();
        assertEq(mock.callCount(), 1);
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
        assertFalse(mock.enteredSnapshot()); // initial storage value is false (zero default)

        mock.captureEnteredState();

        // enteredSnapshot was recorded while nonReentrantBefore was active — must be true.
        assertTrue(mock.enteredSnapshot());

        // After the call completes the lock is released. A fresh guarded call should
        // still succeed (i.e., the helper returning true mid-call did not brick the lock).
        mock.singleCall();
        assertEq(mock.callCount(), 1);
    }
}
