// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";

/// @title AccessControl
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol)
/// @notice AccessControl is a contract module that allows children to implement role-based access
/// control mechanisms. This is a lightweight version that doesn't include enumeration of role members.
/// @dev See {AccessControlEnumerable} if you need to enumerate role members.
contract AccessControl {
    /// @notice Checks whether an account has a specific role.
    /// @param _role The role identifier to check.
    /// @param _account The account address to verify.
    /// @return bool True if the account has the role, false otherwise.
    function hasRole(bytes32 _role, address _account) public view virtual returns (bool) {
        return AccessControlLib.hasRole(_role, _account);
    }

    /// @notice Gets the admin role that controls a specific role.
    /// @param _role The role identifier to query.
    /// @return bytes32 The admin role that can grant or revoke the specified role.
    function getRoleAdmin(bytes32 _role) public view virtual returns (bytes32) {
        return AccessControlLib.getRoleAdmin(_role);
    }

    /// @notice Grants a role to an account.
    /// @param _role The role identifier to grant.
    /// @param _account The account address to grant the role to.
    /// @dev Only callable by accounts holding the admin role for the target role.
    /// Emits a RoleGranted event if the role was not already held by the account.
    function grantRole(bytes32 _role, address _account) public virtual {
        AccessControlLib.grantRole(_role, _account);
    }

    /// @notice Revokes a role from an account.
    /// @param _role The role identifier to revoke.
    /// @param _account The account address to revoke the role from.
    /// @dev Only callable by accounts holding the admin role for the target role.
    /// Emits a RoleRevoked event if the account currently holds the role.
    function revokeRole(bytes32 _role, address _account) public virtual {
        AccessControlLib.revokeRole(_role, _account);
    }

    /// @notice Renounces a role from the caller's account.
    /// @param _role The role identifier to renounce.
    /// @param _callerConfirmation The caller's address as a confirmation parameter.
    /// @dev This allows accounts to lose privileges if compromised (e.g., misplaced keys).
    /// Emits a RoleRevoked event if the caller currently holds the role.
    /// The _callerConfirmation parameter must match msg.sender for security.
    function renounceRole(bytes32 _role, address _callerConfirmation) public virtual {
        AccessControlLib.renounceRole(_role, _callerConfirmation);
    }
}
