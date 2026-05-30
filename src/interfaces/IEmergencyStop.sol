// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IEmergencyStop
/// @notice Interface for the EmergencyStop module — a multi-guardian emergency pause where
///         any guardian can trip the stop, but only an admin can resume operations.
interface IEmergencyStop {
    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @dev Emitted when a guardian trips the emergency stop.
    /// @param guardian The address of the guardian that triggered the stop.
    /// @param reason   A human-readable description of why the stop was triggered.
    event EmergencyStopped(address indexed guardian, string reason);

    /// @dev Emitted when an admin resumes operations after an emergency stop.
    /// @param admin The address of the admin that resumed operations.
    event EmergencyResumed(address indexed admin);

    /// @dev Emitted when a new guardian is added.
    /// @param guardian The address granted guardian status.
    event GuardianAdded(address indexed guardian);

    /// @dev Emitted when a guardian is removed.
    /// @param guardian The address that lost guardian status.
    event GuardianRemoved(address indexed guardian);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @dev Thrown when an operation is blocked because the emergency stop is active.
    error EmergencyStopActive();

    /// @dev Thrown when `emergencyResume` is called but the stop is not active.
    error EmergencyStopNotActive();

    /// @dev Thrown when a caller without the guardian role attempts `emergencyStop`.
    /// @param caller The address that attempted the unauthorized stop.
    error EmergencyStopUnauthorizedGuardian(address caller);

    // -------------------------------------------------------------------------
    // View functions
    // -------------------------------------------------------------------------

    /// @notice Returns whether the emergency stop is currently active.
    /// @return bool True if the system is stopped, false otherwise.
    function isStopped() external view returns (bool);

    /// @notice Returns whether `account` holds the guardian role.
    /// @param account The address to query.
    /// @return bool True if the account is a guardian.
    function isGuardian(address account) external view returns (bool);

    /// @notice Returns the reason string recorded when the emergency stop was last triggered.
    /// @return string The reason for the last emergency stop (empty if never stopped).
    function stoppedReason() external view returns (string memory);

    // -------------------------------------------------------------------------
    // State-changing functions
    // -------------------------------------------------------------------------

    /// @notice Activates the emergency stop.
    /// @dev Requires the caller to hold the guardian role (EMERGENCY_GUARDIAN_ROLE).
    ///      Reverts with `EmergencyStopActive` if the stop is already active.
    ///      Emits `EmergencyStopped`.
    /// @param reason A human-readable description of why the stop is being triggered.
    function emergencyStop(string calldata reason) external;

    /// @notice Resumes operations after an emergency stop.
    /// @dev Requires DEFAULT_ADMIN_ROLE. Reverts with `EmergencyStopNotActive` if not stopped.
    ///      Emits `EmergencyResumed`.
    function emergencyResume() external;

    /// @notice Grants the guardian role to `guardian`.
    /// @dev Requires DEFAULT_ADMIN_ROLE. Emits `GuardianAdded`.
    /// @param guardian The address to grant guardian status.
    function addGuardian(address guardian) external;

    /// @notice Revokes the guardian role from `guardian`.
    /// @dev Requires DEFAULT_ADMIN_ROLE. Emits `GuardianRemoved`.
    /// @param guardian The address to revoke guardian status from.
    function removeGuardian(address guardian) external;
}
