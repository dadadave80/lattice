// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.AccessControl")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ACCESS_CONTROL_STORAGE_SLOT = 0xb914f813e2d49e02dd5aa794466aa4a74f9c100c2b1e98e29e7267020b834d00;

/// @dev `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC165_STORAGE_LOCATION = 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x7965db0b is `type(IAccessControl).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x7965db0b), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IACCESSCONTROL_SLOT = 0xce317eb1da4e1492e501dc3f63d2206e3e9294a33442f09d99ce09cbbaaeae1f;

/// @dev The default admin role is represented by the zero bytes32 value.
/// This role has the highest level of permissions and is the initial admin for all roles by default.
/// It can grant and revoke any role, including itself, so it should be assigned with caution.
bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

struct RoleData {
    mapping(address account => bool) hasRole;
    bytes32 adminRole;
}

/// @notice Struct for storing Access Control information
/// @dev Implements storage layout for role-based access control, including role membership and admin roles.
/// @custom:storage-location erc7201:lattice.storage.AccessControl
struct AccessControlStorage {
    mapping(bytes32 role => RoleData) _roles;
}

/// @title Access Control Library
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol)
/// @notice A library for implementing access control in smart contracts.
library AccessControlLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                           ACCESS CONTROL STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    function accessControlStorage() internal pure returns (AccessControlStorage storage $) {
        assembly {
            $.slot := ACCESS_CONTROL_STORAGE_SLOT
        }
    }

    /// @notice Modifier that checks that an account has a specific role.
    /// @param role The role identifier required to execute the guarded code.
    /// @dev Reverts with an {AccessControlUnauthorizedAccount} error including the required role.
    modifier onlyRole(bytes32 role) {
        checkRole(role);
        _;
    }

    /// @notice Registers support for the IAccessControl interface via ERC165.
    /// @dev Sets the interface ID mapping in storage to true for ERC165 detection.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IACCESSCONTROL_SLOT, true)
        }
    }

    /// @notice Initializes the AccessControl module with a given admin address.
    /// @param _admin The address to be granted the DEFAULT_ADMIN_ROLE.
    /// @dev Can only be called during initialization phase. Requires InitializableLib context.
    function __AccessControl_init(address _admin) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         ACCESS CONTROL OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Checks whether a specific account has been granted a role.
    /// @param _role The role identifier to verify.
    /// @param _account The account address to check.
    /// @return bool True if the account has the role, false otherwise.
    function hasRole(bytes32 _role, address _account) internal view returns (bool) {
        AccessControlStorage storage $ = accessControlStorage();
        return $._roles[_role].hasRole[_account];
    }

    /// @notice Checks if the caller has a specific role and reverts if not.
    /// @param _role The required role identifier.
    /// @dev Uses msg.sender to get the caller. Reverts with AccessControlUnauthorizedAccount if not authorized.
    function checkRole(bytes32 _role) internal view {
        checkRole(_role, msg.sender);
    }

    /// @notice Checks if a specific account has a role and reverts if not.
    /// @param _role The required role identifier.
    /// @param _account The account address to check.
    /// @dev Reverts with an {AccessControlUnauthorizedAccount} error if the account lacks the role.
    function checkRole(bytes32 _role, address _account) internal view {
        if (!hasRole(_role, _account)) {
            revert IAccessControl.AccessControlUnauthorizedAccount(_account, _role);
        }
    }

    /// @notice Retrieves the admin role that controls access to a specific role.
    /// @param _role The role identifier to query.
    /// @return bytes32 The admin role. Use {grantRole} or {revokeRole} to modify admin privileges.
    /// To change a role's admin, use {setRoleAdmin}.
    function getRoleAdmin(bytes32 _role) internal view returns (bytes32) {
        AccessControlStorage storage $ = accessControlStorage();
        return $._roles[_role].adminRole;
    }

    /// @notice Grants a role to an account.
    /// @param role The role identifier to grant.
    /// @param account The account address to grant the role to.
    /// @dev Only callable by accounts holding the admin role for the target role.
    /// May emit a {RoleGranted} event if the role wasn't previously held by the account.
    /// Requirements: the caller must have the admin role of the target role.
    function grantRole(bytes32 role, address account) internal onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    /// @notice Revokes a role from an account.
    /// @param role The role identifier to revoke.
    /// @param account The account address to revoke the role from.
    /// @dev Only callable by accounts holding the admin role for the target role.
    /// May emit a {RoleRevoked} event if the account currently holds the role.
    /// Requirements: the caller must have the admin role of the target role.
    function revokeRole(bytes32 role, address account) internal onlyRole(getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    /// @notice Revokes a role from the calling account.
    /// @param role The role identifier to renounce.
    /// @param callerConfirmation The caller's address as a confirmation parameter.
    /// @dev Allows accounts to lose privileges if compromised (e.g., misplaced keys or compromised devices).
    /// May emit a {RoleRevoked} event if the caller currently holds the role.
    /// Requirements: the callerConfirmation parameter must match the msg.sender for security.
    function renounceRole(bytes32 role, address callerConfirmation) internal {
        if (callerConfirmation != msg.sender) {
            revert IAccessControl.AccessControlBadConfirmation();
        }

        _revokeRole(role, callerConfirmation);
    }

    /// @notice Sets a new admin role for a specific role, gated on the role's *current* admin.
    /// @param role The role identifier to modify.
    /// @param adminRole The new admin role that will control access to the target role.
    /// @dev Reverts {AccessControlUnauthorizedAccount} unless the caller holds the role's current admin
    /// role, then delegates to {_setRoleAdmin}. Emits a {RoleAdminChanged} event.
    function setRoleAdmin(bytes32 role, bytes32 adminRole) internal {
        checkRole(getRoleAdmin(role));
        _setRoleAdmin(role, adminRole);
    }

    /// @notice Internal, UNGATED admin-role setter (mirrors OpenZeppelin's `_setRoleAdmin`).
    /// @param role The role identifier to modify.
    /// @param adminRole The new admin role that will control access to the target role.
    /// @dev Has no access restrictions — callers are responsible for gating (e.g. the public
    /// {setRoleAdmin} wrapper, or a module initializer running in a privileged bootstrap window).
    /// Used during initialization to pin a role's admin (e.g. making a role self-administered) before
    /// any external grant/revoke is possible. Emits a {RoleAdminChanged} event.
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal {
        AccessControlStorage storage $ = accessControlStorage();
        bytes32 previousAdminRole = getRoleAdmin(role);
        $._roles[role].adminRole = adminRole;
        emit IAccessControl.RoleAdminChanged(role, previousAdminRole, adminRole);
    }

    /// @notice Internal function to grant a role to an account.
    /// @param role The role identifier to grant.
    /// @param account The account address to grant the role to.
    /// @return bool True if the role was granted, false if the account already held it.
    /// @dev Internal function without access restrictions. Any caller can execute this.
    /// May emit a {RoleGranted} event.
    function _grantRole(bytes32 role, address account) internal returns (bool) {
        AccessControlStorage storage $ = accessControlStorage();
        if (!hasRole(role, account)) {
            $._roles[role].hasRole[account] = true;
            emit IAccessControl.RoleGranted(role, account, msg.sender);
            return true;
        } else {
            return false;
        }
    }

    /// @notice Internal function to revoke a role from an account.
    /// @param role The role identifier to revoke.
    /// @param account The account address to revoke the role from.
    /// @return bool True if the role was revoked, false if the account didn't hold it.
    /// @dev Internal function without access restrictions. Any caller can execute this.
    /// May emit a {RoleRevoked} event.
    function _revokeRole(bytes32 role, address account) internal returns (bool) {
        AccessControlStorage storage $ = accessControlStorage();
        if (hasRole(role, account)) {
            $._roles[role].hasRole[account] = false;
            emit IAccessControl.RoleRevoked(role, account, msg.sender);
            return true;
        } else {
            return false;
        }
    }
}
