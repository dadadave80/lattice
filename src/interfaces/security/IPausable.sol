// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IPausable
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Pausable.sol)
/// @notice Interface for the Pausable module, providing pause/unpause lifecycle control.
interface IPausable {
    /// @dev Emitted when the contract is paused by `account`.
    /// @param account The address that triggered the pause.
    event Paused(address account);

    /// @dev Emitted when the contract is unpaused by `account`.
    /// @param account The address that triggered the unpause.
    event Unpaused(address account);

    /// @dev Thrown when an action is attempted while the contract is paused.
    error EnforcedPause();

    /// @dev Thrown when an action requires the contract to be paused but it is not.
    error ExpectedPause();

    /// @notice Returns whether the contract is currently paused.
    /// @return bool True if the contract is paused, false otherwise.
    function paused() external view returns (bool);

    /// @notice Pauses the contract, blocking operations guarded by `whenNotPaused`.
    /// @dev Requires the caller to hold the DEFAULT_ADMIN_ROLE.
    function pause() external;

    /// @notice Unpauses the contract, resuming operations guarded by `whenNotPaused`.
    /// @dev Requires the caller to hold the DEFAULT_ADMIN_ROLE.
    function unpause() external;
}
