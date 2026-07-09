// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ReentrancyGuard} from "@lattice/security/ReentrancyGuard.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

/// @title ReentrancyGuardTestFacet
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only facet that drives {ReentrancyGuardLib}'s `nonReentrantBefore/After` lock through REAL
///         diamond delegatecall — the whole point of {ReentrancyGuard}: the lock lives in the diamond's storage
///         and every `this.*` call re-enters the diamond's `fallback` dispatch, so a genuine reentrant call must
///         revert. There is no production ReentrancyGuard facet (it is a guard consumed by other facets), so this
///         facet stands in to exercise the guard on a bare diamond `[ERC165Facet, ReentrancyGuardTestFacet]`.
/// @dev The plain `callCount`/`enteredSnapshot` slots (0/1) are collision-free: the {Diamond} keeps its own
///      bookkeeping and the guard's `_status` in namespaced ERC-7201 slots.
contract ReentrancyGuardTestFacet is ReentrancyGuard {
    /// @notice Tracks successful guarded-call count for assertion purposes.
    uint256 public callCount;

    /// @notice Records the guard state snapshot captured inside a guarded call.
    bool public enteredSnapshot;

    /// @notice A non-reentrant function that increments `callCount`.
    /// @dev Protected by nonReentrantBefore / nonReentrantAfter.
    function singleCall() external {
        ReentrancyGuardLib.nonReentrantBefore();
        callCount++;
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice A non-reentrant function that attempts to call itself recursively through the diamond.
    /// @dev The reentrant call should revert with `ReentrancyGuardReentrantCall`.
    function reentrantAttack() external {
        ReentrancyGuardLib.nonReentrantBefore();
        callCount++;
        // Attempt reentrant call — routes back through the diamond fallback, should revert.
        this.reentrantAttack();
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice A non-reentrant function that calls a secondary non-reentrant function.
    /// @dev Tests mutual exclusion: both use the same lock so the inner call should revert.
    function callInner() external {
        ReentrancyGuardLib.nonReentrantBefore();
        callCount++;
        // Attempt to enter a different guarded function — same lock, should revert.
        this.singleCall();
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Captures `reentrancyGuardEntered()` into `enteredSnapshot` mid-call, then releases the lock.
    /// @dev Used to verify the helper returns true while locked.
    function captureEnteredState() external {
        ReentrancyGuardLib.nonReentrantBefore();
        enteredSnapshot = ReentrancyGuardLib.reentrancyGuardEntered();
        ReentrancyGuardLib.nonReentrantAfter();
    }
}
