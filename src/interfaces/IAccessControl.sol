// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (access/IAccessControl.sol)

pragma solidity >=0.8.4;

/// @title IAccessControl
/// @dev External interface of AccessControl declared to support ERC-165 detection.
interface IAccessControl {
    /// @dev Thrown when an account is missing a required role.
    /// @param account The account that lacks authorization.
    /// @param neededRole The role identifier that the account is missing.
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);

    /// @dev Thrown when function caller confirmation fails during role renunciation.
    /// This prevents accidental role loss due to incorrect address parameter.
    /// @dev NOTE: Don't confuse with {AccessControlUnauthorizedAccount}.
    error AccessControlBadConfirmation();

    /// @dev Emitted when a new admin role is assigned to govern access for another role.
    /// The DEFAULT_ADMIN_ROLE is the initial admin for all roles, though RoleAdminChanged
    /// is not emitted for this initial state.
    /// @param role The role identifier whose admin has changed.
    /// @param previousAdminRole The previous admin role for this role.
    /// @param newAdminRole The new admin role for this role.
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /// @dev Emitted when a role is granted to an account.
    /// The sender is the account that initiated the grant operation (typically the admin).
    /// Expected when using the internal {AccessControl-_grantRole} function.
    /// @param role The role identifier that was granted.
    /// @param account The account that received the role.
    /// @param sender The account that originated the contract call (admin role bearer).
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /// @dev Emitted when a role is revoked from an account.
    /// The sender varies based on the revocation method:
    ///   - if using `revokeRole`, sender is the admin role bearer
    ///   - if using `renounceRole`, sender is the role bearer (i.e., the account losing the role)
    /// @param role The role identifier that was revoked.
    /// @param account The account that lost the role.
    /// @param sender The account that originated the contract call (admin or account itself).
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /// @notice Checks whether an account has been granted a specific role.
    /// @param role The role identifier to verify.
    /// @param account The account address to check.
    /// @return bool True if the account has the role, false otherwise.
    function hasRole(bytes32 role, address account) external view returns (bool);

    /// @notice Retrieves the admin role that controls access to a specific role.
    /// @param role The role identifier to query.
    /// @return bytes32 The admin role that can grant or revoke the specified role.
    /// To change a role's admin, use {AccessControl-_setRoleAdmin}.
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    /// @notice Grants a role to an account.
    /// @param role The role identifier to grant.
    /// @param account The account address to grant the role to.
    /// @dev Emits a {RoleGranted} event if the account didn't already hold the role.
    /// Requirements:
    /// - the caller must have the admin role for the target role.
    function grantRole(bytes32 role, address account) external;

    /// @notice Revokes a role from an account.
    /// @param role The role identifier to revoke.
    /// @param account The account address to revoke the role from.
    /// @dev Emits a {RoleRevoked} event if the account currently holds the role.
    /// Requirements:
    /// - the caller must have the admin role for the target role.
    function revokeRole(bytes32 role, address account) external;

    /// @notice Renounces a role from the calling account.
    /// @param role The role identifier to renounce.
    /// @param callerConfirmation The caller's address as a confirmation parameter.
    /// @dev Allows accounts to lose privileges if compromised (e.g., misplaced keys or compromised devices).
    /// Emits a {RoleRevoked} event if the caller currently holds the role.
    /// Requirements:
    /// - the caller's actual address must match the callerConfirmation parameter for security.
    function renounceRole(bytes32 role, address callerConfirmation) external;
}
