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
}
