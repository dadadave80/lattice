// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessManagerLib} from "@lattice/access/libraries/AccessManagerLib.sol";
import {IAccessManager} from "@lattice/interfaces/access/IAccessManager.sol";

/// @title AccessManager
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/manager/AccessManager.sol)
/// @notice Diamond facet exposing AccessManagerLib.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract AccessManager is IAccessManager {
    function ADMIN_ROLE() external pure virtual override returns (uint64) {
        return AccessManagerLib.ADMIN_ROLE;
    }

    function PUBLIC_ROLE() external pure virtual override returns (uint64) {
        return AccessManagerLib.PUBLIC_ROLE;
    }

    function hasRole(uint64 roleId, address account) external view virtual override returns (bool, uint32) {
        return AccessManagerLib.hasRole(roleId, account);
    }

    function getAccess(uint64 roleId, address account)
        external
        view
        virtual
        override
        returns (uint48, uint32, uint32, uint48)
    {
        return AccessManagerLib.getAccess(roleId, account);
    }

    function getRoleAdmin(uint64 roleId) external view virtual override returns (uint64) {
        return AccessManagerLib.getRoleAdmin(roleId);
    }

    function getRoleGuardian(uint64 roleId) external view virtual override returns (uint64) {
        return AccessManagerLib.getRoleGuardian(roleId);
    }

    function getRoleGrantDelay(uint64 roleId) external view virtual override returns (uint32) {
        return AccessManagerLib.getRoleGrantDelay(roleId);
    }

    function getRoleMembers(uint64 roleId) external view virtual override returns (address[] memory) {
        return AccessManagerLib.getRoleMembers(roleId);
    }

    function getRoleMemberCount(uint64 roleId) external view virtual override returns (uint256) {
        return AccessManagerLib.getRoleMemberCount(roleId);
    }

    function getTargetFunctionRole(address target, bytes4 selector) external view virtual override returns (uint64) {
        return AccessManagerLib.getTargetFunctionRole(target, selector);
    }

    function getTargetAdminDelay(address target) external view virtual override returns (uint32) {
        return AccessManagerLib.getTargetAdminDelay(target);
    }

    function isTargetClosed(address target) external view virtual override returns (bool) {
        return AccessManagerLib.isTargetClosed(target);
    }

    function canCall(address caller, address target, bytes4 selector)
        external
        view
        virtual
        override
        returns (bool, uint32)
    {
        return AccessManagerLib.canCall(caller, target, selector);
    }

    function hashOperation(address caller, address target, bytes calldata data)
        external
        pure
        virtual
        override
        returns (bytes32)
    {
        return AccessManagerLib.hashOperation(caller, target, data);
    }

    function getSchedule(bytes32 operationId) external view virtual override returns (uint48) {
        return AccessManagerLib.getSchedule(operationId);
    }

    function getNonce(bytes32 operationId) external view virtual override returns (uint32) {
        return AccessManagerLib.getNonce(operationId);
    }

    function grantRole(uint64 roleId, address account, uint32 executionDelay) external virtual override {
        AccessManagerLib.grantRole(roleId, account, executionDelay);
    }

    function revokeRole(uint64 roleId, address account) external virtual override {
        AccessManagerLib.revokeRole(roleId, account);
    }

    function renounceRole(uint64 roleId, address callerConfirmation) external virtual override {
        AccessManagerLib.renounceRole(roleId, callerConfirmation);
    }

    function setRoleAdmin(uint64 roleId, uint64 admin) external virtual override {
        AccessManagerLib.setRoleAdmin(roleId, admin);
    }

    function setRoleGuardian(uint64 roleId, uint64 guardian) external virtual override {
        AccessManagerLib.setRoleGuardian(roleId, guardian);
    }

    function setGrantDelay(uint64 roleId, uint32 newDelay) external virtual override {
        AccessManagerLib.setGrantDelay(roleId, newDelay);
    }

    function labelRole(uint64 roleId, string calldata label) external virtual override {
        AccessManagerLib.labelRole(roleId, label);
    }

    function setTargetFunctionRole(address target, bytes4[] calldata selectors, uint64 roleId)
        external
        virtual
        override
    {
        AccessManagerLib.setTargetFunctionRole(target, selectors, roleId);
    }

    function setTargetAdminDelay(address target, uint32 newDelay) external virtual override {
        AccessManagerLib.setTargetAdminDelay(target, newDelay);
    }

    function setTargetClosed(address target, bool closed) external virtual override {
        AccessManagerLib.setTargetClosed(target, closed);
    }

    function schedule(address target, bytes calldata data, uint48 when)
        external
        virtual
        override
        returns (bytes32, uint32)
    {
        return AccessManagerLib.schedule(target, data, when);
    }

    function execute(address target, bytes calldata data) external payable virtual override returns (uint32) {
        return AccessManagerLib.execute(target, data);
    }

    function cancel(address caller, address target, bytes calldata data) external virtual override returns (uint32) {
        return AccessManagerLib.cancel(caller, target, data);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect AccessManager methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `ADMIN_ROLE()` 0x75b238fc
    ///      `PUBLIC_ROLE()` 0x3ca7c02a
    ///      `canCall(address,address,bytes4)` 0xb7009613
    ///      `cancel(address,address,bytes)` 0xd6bb62c6
    ///      `execute(address,bytes)` 0x1cff79cd
    ///      `getAccess(uint64,address)` 0x3078f114
    ///      `getNonce(bytes32)` 0x4136a33c
    ///      `getRoleAdmin(uint64)` 0x530dd456
    ///      `getRoleGrantDelay(uint64)` 0x12be8727
    ///      `getRoleGuardian(uint64)` 0x0b0a93ba
    ///      `getRoleMemberCount(uint64)` 0xfc8610d1
    ///      `getRoleMembers(uint64)` 0xa5808e2f
    ///      `getSchedule(bytes32)` 0x3adc277a
    ///      `getTargetAdminDelay(address)` 0x4c1da1e2
    ///      `getTargetFunctionRole(address,bytes4)` 0x6d5115bd
    ///      `grantRole(uint64,address,uint32)` 0x25c471a0
    ///      `hasRole(uint64,address)` 0xd1f856ee
    ///      `hashOperation(address,address,bytes)` 0xabd9bd2a
    ///      `isTargetClosed(address)` 0xa166aa89
    ///      `labelRole(uint64,string)` 0x853551b8
    ///      `renounceRole(uint64,address)` 0xfe0776f5
    ///      `revokeRole(uint64,address)` 0xb7d2b162
    ///      `schedule(address,bytes,uint48)` 0xf801a698
    ///      `setGrantDelay(uint64,uint32)` 0xa64d95ce
    ///      `setRoleAdmin(uint64,uint64)` 0x30cae187
    ///      `setRoleGuardian(uint64,uint64)` 0x52962952
    ///      `setTargetAdminDelay(address,uint32)` 0xd22b5989
    ///      `setTargetClosed(address,bool)` 0x167bd395
    ///      `setTargetFunctionRole(address,bytes4[],uint64)` 0x08d6122d
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors =
            hex"75b238fc3ca7c02ab7009613d6bb62c61cff79cd3078f1144136a33c530dd45612be87270b0a93bafc8610d1a5808e2f3adc277a4c1da1e26d5115bd25c471a0d1f856eeabd9bd2aa166aa89853551b8fe0776f5b7d2b162f801a698a64d95ce30cae18752962952d22b5989167bd39508d6122d";
    }
}
