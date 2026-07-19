// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IReentrancyGuard
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuard.sol)
/// @notice Interface for the ReentrancyGuard module.
/// @dev This interface defines the error used to guard against reentrant calls.
/// ReentrancyGuard exposes no external functions — protection comes from the
/// {ReentrancyGuard} mixin's modifiers over {ReentrancyGuardLib}. There is no
/// init and no ERC-165 registration (an error-only interfaceId would be 0x00000000).
interface IReentrancyGuard {
    /// @dev Thrown when a reentrant call is detected.
    error ReentrancyGuardReentrantCall();
}
