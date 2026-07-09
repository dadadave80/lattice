// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlEnumerableLib, AccessControlLib} from "@lattice/access/libraries/AccessControlEnumerableLib.sol";
import {IAccessControl, IAccessControlEnumerable} from "@lattice/interfaces/access/IAccessControlEnumerable.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";

/// @title AccessControlEnumerable
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/extensions/AccessControlEnumerable.sol)
/// @notice Diamond facet exposing AccessControl + per-role address enumeration.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract AccessControlEnumerable is AccessControl, IAccessControlEnumerable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @inheritdoc IAccessControlEnumerable
    function getRoleMember(bytes32 role, uint256 index) public view virtual override returns (address) {
        return AccessControlEnumerableLib.getRoleMember(role, index);
    }

    /// @inheritdoc IAccessControlEnumerable
    function getRoleMemberCount(bytes32 role) public view virtual override returns (uint256) {
        return AccessControlEnumerableLib.getRoleMemberCount(role);
    }

    /// @inheritdoc IAccessControlEnumerable
    function getRoleMembers(bytes32 role) public view virtual override returns (address[] memory) {
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
        AccessControlEnumerableLib.grantRole(_role, _account);
    }

    /// @inheritdoc IAccessControl
    function revokeRole(bytes32 _role, address _account) public virtual override(AccessControl, IAccessControl) {
        AccessControlEnumerableLib.revokeRole(_role, _account);
    }

    /// @inheritdoc IAccessControl
    function renounceRole(bytes32 _role, address _callerConfirmation)
        public
        virtual
        override(AccessControl, IAccessControl)
    {
        AccessControlEnumerableLib.renounceRole(_role, _callerConfirmation);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect AccessControlEnumerable methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `getRoleAdmin(bytes32)` 0x248a9ca3
    ///      `getRoleMember(bytes32,uint256)` 0x9010d07c
    ///      `getRoleMemberCount(bytes32)` 0xca15c873
    ///      `getRoleMembers(bytes32)` 0xa3246ad3
    ///      `grantRole(bytes32,address)` 0x2f2ff15d
    ///      `hasRole(bytes32,address)` 0x91d14854
    ///      `renounceRole(bytes32,address)` 0x36568abe
    ///      `revokeRole(bytes32,address)` 0xd547741f
    function exportSelectors() external pure virtual override returns (bytes memory selectors) {
        selectors = hex"248a9ca39010d07cca15c873a3246ad32f2ff15d91d1485436568abed547741f";
    }
}
