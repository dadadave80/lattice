// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlEnumerableLib} from "@lattice/access/libraries/AccessControlEnumerableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {IAccessControlEnumerable} from "@lattice/interfaces/IAccessControlEnumerable.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";

/// @title AccessControlEnumerable
/// @notice Diamond facet exposing AccessControl + per-role address enumeration.
contract AccessControlEnumerable is AccessControl, IAccessControlEnumerable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @inheritdoc IAccessControlEnumerable
    function getRoleMember(bytes32 role, uint256 i) external view virtual override returns (address) {
        return AccessControlEnumerableLib.getRoleMember(role, i);
    }

    /// @inheritdoc IAccessControlEnumerable
    function getRoleMemberCount(bytes32 role) external view virtual override returns (uint256) {
        return AccessControlEnumerableLib.getRoleMemberCount(role);
    }

    /// @inheritdoc IAccessControlEnumerable
    function getRoleMembers(bytes32 role) external view virtual override returns (address[] memory) {
        return AccessControlEnumerableLib.getRoleMembers(role);
    }

    /// @inheritdoc IAccessControl
    function hasRole(bytes32 _role, address _account)
        public
        view
        virtual
        override(AccessControl, IAccessControl)
        returns (bool)
    {
        return AccessControlLib.hasRole(_role, _account);
    }

    /// @inheritdoc IAccessControl
    function getRoleAdmin(bytes32 _role) public view virtual override(AccessControl, IAccessControl) returns (bytes32) {
        return AccessControlLib.getRoleAdmin(_role);
    }

    /// @inheritdoc IAccessControl
    function grantRole(bytes32 _role, address _account) public virtual override(AccessControl, IAccessControl) {
        AccessControlLib.checkRole(AccessControlLib.getRoleAdmin(_role));
        AccessControlEnumerableLib.grantRole(_role, _account);
    }

    /// @inheritdoc IAccessControl
    function revokeRole(bytes32 _role, address _account) public virtual override(AccessControl, IAccessControl) {
        AccessControlLib.checkRole(AccessControlLib.getRoleAdmin(_role));
        AccessControlEnumerableLib.revokeRole(_role, _account);
    }

    /// @inheritdoc IAccessControl
    function renounceRole(bytes32 _role, address _callerConfirmation)
        public
        virtual
        override(AccessControl, IAccessControl)
    {
        super.renounceRole(_role, _callerConfirmation);
        // Clean up the member-set entry — `remove` returns false if absent, which is safe.
        AccessControlEnumerableLib.accessControlEnumerableStorage()._roleMembers[_role].remove(_callerConfirmation);
    }
}
