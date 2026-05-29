// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IReentrancyGuard
/// @notice Interface for the ReentrancyGuard module.
/// @dev This interface defines the error used to guard against reentrant calls.
/// ReentrancyGuard exposes no external functions — it is used as an inherited
/// base contract and registered via ERC-165 in the Diamond's init phase.
interface IReentrancyGuard {
    /// @dev Thrown when a reentrant call is detected.
    error ReentrancyGuardReentrantCall();
}
