// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IAccessManager} from "@lattice/interfaces/IAccessManager.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";
import {TimelockLib} from "@lattice/utils/libraries/TimelockLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.AccessManager")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ACCESS_MANAGER_STORAGE_SLOT = 0x031c2bc21c63b497895ca319b75b15a6c2f2e4b0e91bbd5327f580843bca1a00;

/// @dev `0x8fc52f86` is `type(IAccessManager).interfaceId`.
bytes32 constant ERC165_MAP_IACCESSMANAGER_SLOT = 0xa0825c9ce05c3e98cbd409c12bc8bdadc253d720dbb80af60f4b2f3807f3c1dd;

struct Delay {
    uint32 value;
    uint32 pendingValue;
    uint48 effectAt;
}

struct Access {
    uint48 since;
    Delay delay;
}

struct Role {
    uint64 admin;
    uint64 guardian;
    uint32 grantDelay;
    uint48 grantDelayEffectAt;
    uint32 pendingGrantDelay;
}

struct TargetConfig {
    mapping(bytes4 selector => uint64 roleId) allowedRoles;
    uint32 adminDelay;
    uint48 adminDelayEffectAt;
    uint32 pendingAdminDelay;
    bool closed;
}

/// @custom:storage-location erc7201:lattice.storage.AccessManager
struct AccessManagerStorage {
    mapping(uint64 roleId => Role) _roles;
    mapping(uint64 roleId => mapping(address account => Access)) _access;
    mapping(uint64 roleId => EnumerableSet.AddressSet) _roleMembers;
    mapping(address target => TargetConfig) _targets;
    TimelockLib.MultiSchedule _operationQueue;
    mapping(bytes32 operationId => uint32 nonce) _nonces;
    uint32 _nextNonce;
}

/// @title AccessManagerLib
/// @notice Logic for IAccessManager.
library AccessManagerLib {
    using EnumerableSet for EnumerableSet.AddressSet;
    using TimelockLib for TimelockLib.MultiSchedule;

    uint64 internal constant ADMIN_ROLE = 0;
    uint64 internal constant PUBLIC_ROLE = type(uint64).max;

    /// @notice Scheduled operations expire after this many seconds past `readyAt`.
    uint32 internal constant EXPIRATION = 1 weeks;

    function accessManagerStorage() internal pure returns (AccessManagerStorage storage $) {
        assembly {
            $.slot := ACCESS_MANAGER_STORAGE_SLOT
        }
    }

    function __AccessManager_init(address initialAdmin) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        if (initialAdmin == address(0)) revert IAccessManager.AccessManagerInvalidInitialAdmin();
        _grantRoleInternal(ADMIN_ROLE, initialAdmin, 0, true);
        registerInterface();
    }

    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IACCESSMANAGER_SLOT, true)
        }
    }

    // ---- Hashing ----

    function hashOperation(address caller, address target, bytes calldata data) internal pure returns (bytes32) {
        return keccak256(abi.encode(caller, target, data));
    }

    // ---- Role queries ----

    function hasRole(uint64 roleId, address account) internal view returns (bool isMember, uint32 executionDelay) {
        if (roleId == PUBLIC_ROLE) return (true, 0);
        Access storage a = accessManagerStorage()._access[roleId][account];
        isMember = a.since != 0 && block.timestamp >= a.since;
        executionDelay = isMember ? _effectiveDelay(a.delay) : 0;
    }

    function getAccess(uint64 roleId, address account)
        internal
        view
        returns (uint48 since, uint32 currentDelay, uint32 pendingDelay, uint48 effect)
    {
        Access storage a = accessManagerStorage()._access[roleId][account];
        return (a.since, a.delay.value, a.delay.pendingValue, a.delay.effectAt);
    }

    function getRoleAdmin(uint64 roleId) internal view returns (uint64) {
        return accessManagerStorage()._roles[roleId].admin;
    }

    function getRoleGuardian(uint64 roleId) internal view returns (uint64) {
        return accessManagerStorage()._roles[roleId].guardian;
    }

    function getRoleGrantDelay(uint64 roleId) internal view returns (uint32) {
        Role storage r = accessManagerStorage()._roles[roleId];
        if (r.grantDelayEffectAt != 0 && block.timestamp >= r.grantDelayEffectAt) {
            return r.pendingGrantDelay;
        }
        return r.grantDelay;
    }

    function getRoleMembers(uint64 roleId) internal view returns (address[] memory) {
        return accessManagerStorage()._roleMembers[roleId].values();
    }

    function getRoleMemberCount(uint64 roleId) internal view returns (uint256) {
        return accessManagerStorage()._roleMembers[roleId].length();
    }

    // ---- Target queries ----

    function getTargetFunctionRole(address target, bytes4 selector) internal view returns (uint64) {
        return accessManagerStorage()._targets[target].allowedRoles[selector];
    }

    function getTargetAdminDelay(address target) internal view returns (uint32) {
        TargetConfig storage t = accessManagerStorage()._targets[target];
        if (t.adminDelayEffectAt != 0 && block.timestamp >= t.adminDelayEffectAt) {
            return t.pendingAdminDelay;
        }
        return t.adminDelay;
    }

    function isTargetClosed(address target) internal view returns (bool) {
        return accessManagerStorage()._targets[target].closed;
    }

    function canCall(address caller, address target, bytes4 selector)
        internal
        view
        returns (bool immediate, uint32 delay)
    {
        AccessManagerStorage storage $ = accessManagerStorage();
        if ($._targets[target].closed) return (false, 0);
        uint64 roleId = $._targets[target].allowedRoles[selector];
        if (roleId == PUBLIC_ROLE) return (true, 0);
        (bool isMember, uint32 executionDelay) = hasRole(roleId, caller);
        if (!isMember) return (false, 0);
        if (executionDelay == 0) return (true, 0);
        return (false, executionDelay);
    }

    function getSchedule(bytes32 operationId) internal view returns (uint48) {
        return accessManagerStorage()._operationQueue.readyAt(operationId);
    }

    function getNonce(bytes32 operationId) internal view returns (uint32) {
        return accessManagerStorage()._nonces[operationId];
    }

    // ---- Role management ----

    function grantRole(uint64 roleId, address account, uint32 executionDelay) internal {
        _checkRoleAdmin(roleId);
        if (roleId == ADMIN_ROLE || roleId == PUBLIC_ROLE) {
            revert IAccessManager.AccessManagerLockedRole(roleId);
        }
        _grantRoleInternal(roleId, account, executionDelay, true);
    }

    function revokeRole(uint64 roleId, address account) internal {
        _checkRoleAdmin(roleId);
        if (roleId == ADMIN_ROLE || roleId == PUBLIC_ROLE) {
            revert IAccessManager.AccessManagerLockedRole(roleId);
        }
        _revokeRoleInternal(roleId, account);
    }

    function renounceRole(uint64 roleId, address callerConfirmation) internal {
        if (callerConfirmation != ContextLib.msgSender()) {
            revert IAccessManager.AccessManagerBadConfirmation();
        }
        if (roleId == ADMIN_ROLE || roleId == PUBLIC_ROLE) {
            revert IAccessManager.AccessManagerLockedRole(roleId);
        }
        _revokeRoleInternal(roleId, callerConfirmation);
    }

    function setRoleAdmin(uint64 roleId, uint64 admin) internal {
        _checkAdmin();
        if (roleId == ADMIN_ROLE || roleId == PUBLIC_ROLE) {
            revert IAccessManager.AccessManagerLockedRole(roleId);
        }
        accessManagerStorage()._roles[roleId].admin = admin;
        emit IAccessManager.RoleAdminChanged(roleId, admin);
    }

    function setRoleGuardian(uint64 roleId, uint64 guardian) internal {
        _checkAdmin();
        if (roleId == ADMIN_ROLE || roleId == PUBLIC_ROLE) {
            revert IAccessManager.AccessManagerLockedRole(roleId);
        }
        accessManagerStorage()._roles[roleId].guardian = guardian;
        emit IAccessManager.RoleGuardianChanged(roleId, guardian);
    }

    function setGrantDelay(uint64 roleId, uint32 newDelay) internal {
        _checkAdmin();
        if (roleId == ADMIN_ROLE || roleId == PUBLIC_ROLE) {
            revert IAccessManager.AccessManagerLockedRole(roleId);
        }
        Role storage r = accessManagerStorage()._roles[roleId];
        uint32 currentDelay = getRoleGrantDelay(roleId);
        uint48 effectAt;
        if (newDelay < currentDelay) {
            r.grantDelay = newDelay;
            effectAt = uint48(block.timestamp);
            r.pendingGrantDelay = 0;
            r.grantDelayEffectAt = 0;
        } else {
            r.pendingGrantDelay = newDelay;
            effectAt = uint48(block.timestamp + EXPIRATION);
            r.grantDelayEffectAt = effectAt;
        }
        emit IAccessManager.RoleGrantDelayChanged(roleId, newDelay, effectAt);
    }

    function labelRole(uint64 roleId, string calldata label) internal {
        _checkAdmin();
        if (roleId == ADMIN_ROLE || roleId == PUBLIC_ROLE) {
            revert IAccessManager.AccessManagerLockedRole(roleId);
        }
        emit IAccessManager.RoleLabel(roleId, label);
    }

    function setTargetFunctionRole(address target, bytes4[] calldata selectors, uint64 roleId) internal {
        _checkAdmin();
        AccessManagerStorage storage $ = accessManagerStorage();
        for (uint256 i = 0; i < selectors.length; i++) {
            $._targets[target].allowedRoles[selectors[i]] = roleId;
            emit IAccessManager.TargetFunctionRoleUpdated(target, selectors[i], roleId);
        }
    }

    function setTargetAdminDelay(address target, uint32 newDelay) internal {
        _checkAdmin();
        TargetConfig storage t = accessManagerStorage()._targets[target];
        uint48 effectAt;
        if (newDelay < t.adminDelay) {
            t.adminDelay = newDelay;
            effectAt = uint48(block.timestamp);
            t.pendingAdminDelay = 0;
            t.adminDelayEffectAt = 0;
        } else {
            t.pendingAdminDelay = newDelay;
            effectAt = uint48(block.timestamp + EXPIRATION);
            t.adminDelayEffectAt = effectAt;
        }
        emit IAccessManager.TargetAdminDelayUpdated(target, newDelay, effectAt);
    }

    function setTargetClosed(address target, bool closed) internal {
        _checkAdmin();
        accessManagerStorage()._targets[target].closed = closed;
        emit IAccessManager.TargetClosed(target, closed);
    }

    // ---- Operation scheduling ----

    function schedule(address target, bytes calldata data, uint48 when)
        internal
        returns (bytes32 operationId, uint32 nonce)
    {
        address caller = ContextLib.msgSender();
        uint32 delay = _checkCanSchedule(caller, target, data);
        operationId = hashOperation(caller, target, data);
        uint48 effectiveWhen;
        (nonce, effectiveWhen) = _writeSchedule(operationId, when, delay);
        emit IAccessManager.OperationScheduled(operationId, nonce, effectiveWhen, caller, target, data);
    }

    function execute(address target, bytes calldata data) internal returns (uint32 nonce) {
        address caller = ContextLib.msgSender();
        (bool immediate, uint32 delay) = canCall(caller, target, bytes4(data[0:4]));
        bytes32 operationId = hashOperation(caller, target, data);
        AccessManagerStorage storage $ = accessManagerStorage();
        nonce = $._nonces[operationId];

        if (immediate && delay == 0) {
            // No schedule needed
        } else if (delay > 0) {
            uint48 readyAt = $._operationQueue.readyAt(operationId);
            if (readyAt == 0) revert IAccessManager.AccessManagerNotScheduled(operationId);
            if (block.timestamp < readyAt) revert IAccessManager.AccessManagerNotReady(operationId);
            if (block.timestamp > uint256(readyAt) + EXPIRATION) {
                revert IAccessManager.AccessManagerExpired(operationId);
            }
            $._operationQueue._readyAt[operationId] = 0;
        } else {
            revert IAccessManager.AccessManagerUnauthorizedAccount(
                caller, getTargetFunctionRole(target, bytes4(data[0:4]))
            );
        }

        emit IAccessManager.OperationExecuted(operationId, nonce);

        (bool ok,) = target.call{value: msg.value}(data);
        require(ok, "AccessManager: target call failed");
    }

    function cancel(address caller, address target, bytes calldata data) internal returns (uint32 nonce) {
        address msgSender = ContextLib.msgSender();
        bytes32 operationId = hashOperation(caller, target, data);
        AccessManagerStorage storage $ = accessManagerStorage();
        if (!$._operationQueue.isPending(operationId)) {
            revert IAccessManager.AccessManagerNotScheduled(operationId);
        }

        if (msgSender != caller) {
            bytes4 selector = bytes4(data[0:4]);
            uint64 roleId = $._targets[target].allowedRoles[selector];
            uint64 guardian = $._roles[roleId].guardian;
            (bool isGuardian,) = hasRole(guardian, msgSender);
            if (!isGuardian) revert IAccessManager.AccessManagerUnauthorizedCancel(msgSender, target);
        }

        $._operationQueue._readyAt[operationId] = 0;
        nonce = $._nonces[operationId];
        emit IAccessManager.OperationCanceled(operationId, nonce);
    }

    // ---- Internal helpers ----

    function _effectiveDelay(Delay storage d) private view returns (uint32) {
        if (d.effectAt != 0 && block.timestamp >= d.effectAt) return d.pendingValue;
        return d.value;
    }

    function _grantRoleInternal(uint64 roleId, address account, uint32 executionDelay, bool emitEvent) private {
        AccessManagerStorage storage $ = accessManagerStorage();
        Access storage a = $._access[roleId][account];
        bool isNewMember = a.since == 0;
        if (isNewMember) {
            uint48 since = uint48(block.timestamp) + uint48(getRoleGrantDelay(roleId));
            a.since = since;
            a.delay.value = executionDelay;
            $._roleMembers[roleId].add(account);
            if (emitEvent) {
                emit IAccessManager.RoleGranted(roleId, account, executionDelay, since, true);
            }
        } else {
            if (a.delay.value != executionDelay) {
                a.delay.value = executionDelay;
                if (emitEvent) {
                    emit IAccessManager.RoleGranted(roleId, account, executionDelay, a.since, false);
                }
            }
        }
    }

    function _revokeRoleInternal(uint64 roleId, address account) private {
        AccessManagerStorage storage $ = accessManagerStorage();
        if ($._access[roleId][account].since == 0) return;
        delete $._access[roleId][account];
        $._roleMembers[roleId].remove(account);
        emit IAccessManager.RoleRevoked(roleId, account);
    }

    function _checkAdmin() private view {
        (bool isMember,) = hasRole(ADMIN_ROLE, ContextLib.msgSender());
        if (!isMember) revert IAccessManager.AccessManagerUnauthorizedAccount(ContextLib.msgSender(), ADMIN_ROLE);
    }

    function _checkRoleAdmin(uint64 roleId) private view {
        uint64 adminRole = accessManagerStorage()._roles[roleId].admin;
        (bool isMember,) = hasRole(adminRole, ContextLib.msgSender());
        if (!isMember) revert IAccessManager.AccessManagerUnauthorizedAccount(ContextLib.msgSender(), adminRole);
    }

    /// @dev Validates that `caller` may schedule a call to `target` with `data` and returns
    ///      the required execution delay. Reverts if the caller has no access at all or has
    ///      immediate access (no schedule needed).
    function _checkCanSchedule(address caller, address target, bytes calldata data)
        private
        view
        returns (uint32 delay)
    {
        (bool immediate, uint32 d) = canCall(caller, target, bytes4(data[0:4]));
        if (!immediate && d == 0) {
            revert IAccessManager.AccessManagerUnauthorizedAccount(
                caller, getTargetFunctionRole(target, bytes4(data[0:4]))
            );
        }
        if (immediate && d == 0) {
            revert IAccessManager.AccessManagerNotScheduled(hashOperation(caller, target, data));
        }
        delay = d;
    }

    /// @dev Writes the scheduled operation to storage and returns the assigned nonce and
    ///      the effective (clamped) schedule timestamp.
    function _writeSchedule(bytes32 operationId, uint48 when, uint32 delay)
        private
        returns (uint32 nonce, uint48 effectiveWhen)
    {
        AccessManagerStorage storage $ = accessManagerStorage();
        if ($._operationQueue.isPending(operationId)) {
            revert IAccessManager.AccessManagerAlreadyScheduled(operationId);
        }
        uint48 minWhen = uint48(block.timestamp) + delay;
        effectiveWhen = when < minWhen ? minWhen : when;
        $._operationQueue._readyAt[operationId] = effectiveWhen;
        nonce = ++$._nextNonce;
        $._nonces[operationId] = nonce;
    }
}
