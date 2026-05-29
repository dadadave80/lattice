// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";

/// @title IAccessControlTimed
/// @notice Extends IAccessControl with per-grant (start, expires) windows.
///         `hasRole` returns false outside the window.
interface IAccessControlTimed is IAccessControl {
    /// @notice Emitted when a role is granted with a non-default time window.
    event RoleGrantedTimed(
        bytes32 indexed role, address indexed account, address indexed sender, uint48 start, uint48 expires
    );

    /// @notice Emitted when an existing grant's expiry is pushed forward via `extendRole`.
    event RoleExpiryUpdated(bytes32 indexed role, address indexed account, address indexed sender, uint48 newExpires);

    /// @notice `expires` is non-zero but already at or before `block.timestamp`.
    error AccessControlTimedExpiryInPast(uint48 expires);

    /// @notice `expires` is non-zero but earlier than `start`.
    error AccessControlTimedInvalidWindow(uint48 start, uint48 expires);

    /// @notice `extendRole` was called with `newExpires <= currentExpires`.
    error AccessControlTimedExpiryNotExtended(uint48 currentExpires, uint48 newExpires);

    /// @notice `extendRole` was called for an account that does not hold the role.
    error AccessControlTimedRoleNotHeld(bytes32 role, address account);

    function grantRoleTimed(bytes32 role, address account, uint48 start, uint48 expires) external;
    function extendRole(bytes32 role, address account, uint48 newExpires) external;
    function roleExpiration(bytes32 role, address account) external view returns (uint48 start, uint48 expires);
}
