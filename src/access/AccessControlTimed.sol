// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AccessControlTimedLib} from "@lattice/access/libraries/AccessControlTimedLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {IAccessControlTimed} from "@lattice/interfaces/IAccessControlTimed.sol";

/// @title AccessControlTimed
/// @notice Diamond facet exposing AccessControl + per-grant (start, expires) windows.
contract AccessControlTimed is AccessControl, IAccessControlTimed {
    /// @inheritdoc IAccessControlTimed
    function grantRoleTimed(bytes32 role, address account, uint48 start, uint48 expires) external virtual override {
        AccessControlLib.checkRole(AccessControlLib.getRoleAdmin(role));
        AccessControlTimedLib.grantRoleTimed(role, account, start, expires);
    }

    /// @inheritdoc IAccessControlTimed
    function extendRole(bytes32 role, address account, uint48 newExpires) external virtual override {
        AccessControlLib.checkRole(AccessControlLib.getRoleAdmin(role));
        AccessControlTimedLib.extendRole(role, account, newExpires);
    }

    /// @inheritdoc IAccessControlTimed
    function roleExpiration(bytes32 role, address account)
        external
        view
        virtual
        override
        returns (uint48 start, uint48 expires)
    {
        return AccessControlTimedLib.roleExpiration(role, account);
    }

    /// @inheritdoc IAccessControl
    function hasRole(bytes32 _role, address _account)
        public
        view
        virtual
        override(AccessControl, IAccessControl)
        returns (bool)
    {
        return AccessControlTimedLib.hasRole(_role, _account);
    }

    /// @inheritdoc IAccessControl
    function getRoleAdmin(bytes32 _role) public view virtual override(AccessControl, IAccessControl) returns (bytes32) {
        return AccessControlLib.getRoleAdmin(_role);
    }

    /// @inheritdoc IAccessControl
    function grantRole(bytes32 _role, address _account) public virtual override(AccessControl, IAccessControl) {
        AccessControlLib.checkRole(AccessControlLib.getRoleAdmin(_role));
        AccessControlTimedLib.grantRoleTimed(_role, _account, uint48(block.timestamp), 0);
    }

    /// @inheritdoc IAccessControl
    function revokeRole(bytes32 _role, address _account) public virtual override(AccessControl, IAccessControl) {
        AccessControlLib.checkRole(AccessControlLib.getRoleAdmin(_role));
        AccessControlTimedLib.revokeRoleTimed(_role, _account);
    }

    /// @inheritdoc IAccessControl
    function renounceRole(bytes32 _role, address _callerConfirmation)
        public
        virtual
        override(AccessControl, IAccessControl)
    {
        super.renounceRole(_role, _callerConfirmation);
        delete AccessControlTimedLib.accessControlTimedStorage()._timings[_role][_callerConfirmation];
    }
}
