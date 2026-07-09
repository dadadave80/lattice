// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AccessControlTimedLib} from "@lattice/access/libraries/AccessControlTimedLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IAccessControlTimed} from "@lattice/interfaces/access/IAccessControlTimed.sol";

/// @title AccessControlTimed
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol)
/// @notice Diamond facet exposing AccessControl + per-grant (start, expires) windows.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract AccessControlTimed is AccessControl, IAccessControlTimed {
    /// @inheritdoc IAccessControlTimed
    function grantRoleTimed(bytes32 role, address account, uint48 start, uint48 expires) external virtual override {
        AccessControlTimedLib.grantRoleTimed(role, account, start, expires);
    }

    /// @inheritdoc IAccessControlTimed
    function extendRole(bytes32 role, address account, uint48 newExpires) external virtual override {
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
        AccessControlTimedLib.grantRole(_role, _account);
    }

    /// @inheritdoc IAccessControl
    function revokeRole(bytes32 _role, address _account) public virtual override(AccessControl, IAccessControl) {
        AccessControlTimedLib.revokeRole(_role, _account);
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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect AccessControlTimed methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `extendRole(bytes32,address,uint48)` 0xa6db71fa
    ///      `getRoleAdmin(bytes32)` 0x248a9ca3
    ///      `grantRole(bytes32,address)` 0x2f2ff15d
    ///      `grantRoleTimed(bytes32,address,uint48,uint48)` 0x701eb66a
    ///      `hasRole(bytes32,address)` 0x91d14854
    ///      `renounceRole(bytes32,address)` 0x36568abe
    ///      `revokeRole(bytes32,address)` 0xd547741f
    ///      `roleExpiration(bytes32,address)` 0x83a045f1
    function exportSelectors() external pure virtual override returns (bytes memory selectors) {
        selectors = hex"a6db71fa248a9ca32f2ff15d701eb66a91d1485436568abed547741f83a045f1";
    }
}
