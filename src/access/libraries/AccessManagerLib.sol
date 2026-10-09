// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAccessManaged} from "@lattice/interfaces/access/IAccessManaged.sol";
import {IAccessManager} from "@lattice/interfaces/access/IAccessManager.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {TimelockLib} from "@lattice/utils/libraries/TimelockLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.AccessManager")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ACCESS_MANAGER_STORAGE_SLOT = 0x031c2bc21c63b497895ca319b75b15a6c2f2e4b0e91bbd5327f580843bca1a00;

/// @dev `0x03fde054` is `type(IAccessManager).interfaceId` (includes updateAuthority and consumeScheduledOp).
/// `keccak256(abi.encode(bytes4(0x03fde054), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IACCESSMANAGER_SLOT = 0xe8225b256c9522a08c27f0d5ba22c2c153d632cc7b7a99a5ed27141b67ebedd9;

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
    /// @dev `keccak256(abi.encode(target, selector))` of the call {AccessManagerLib.execute} is making, or the
    ///      enclosing call's id (0 outside any `execute`). Regular storage, as in OZ: EIP-1153 is not assumed.
    bytes32 _executionId;
}

/// @title AccessManagerLib
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/manager/AccessManager.sol)
/// @notice Logic for IAccessManager.
library AccessManagerLib {
    using EnumerableSet for EnumerableSet.AddressSet;
    using TimelockLib for TimelockLib.MultiSchedule;

    uint64 internal constant ADMIN_ROLE = 0;
    uint64 internal constant PUBLIC_ROLE = type(uint64).max;

    /// @notice Scheduled operations expire after this many seconds past `readyAt`.
    uint32 internal constant EXPIRATION = 1 weeks;

    /// @notice Minimum setback applied when changing delays.
    uint32 internal constant MIN_SETBACK = 5 days;

    function accessManagerStorage() internal pure returns (AccessManagerStorage storage $) {
        assembly {
            $.slot := ACCESS_MANAGER_STORAGE_SLOT
        }
    }

    function __AccessManager_init(address initialAdmin) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        if (initialAdmin == address(0)) revert IAccessManager.AccessManagerInvalidInitialAdmin();
        _grantRoleInternal(ADMIN_ROLE, initialAdmin, 0);
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

    /// @dev OZ `Time.Delay.getFull`: a pending execution delay already in force is reported as the current one,
    ///      with nothing pending.
    function getAccess(uint64 roleId, address account)
        internal
        view
        returns (uint48 since, uint32 currentDelay, uint32 pendingDelay, uint48 effect)
    {
        Access storage a = accessManagerStorage()._access[roleId][account];
        Delay memory d = a.delay;
        if (d.effectAt != 0 && block.timestamp >= d.effectAt) return (a.since, d.pendingValue, 0, 0);
        return (a.since, d.value, d.pendingValue, d.effectAt);
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

    /// @notice Whether `caller` may call `selector` on `target` now (`immediate`) or after scheduling (`delay`).
    /// @dev The manager itself is an authorized caller only while {execute} is calling that exact
    ///      (`target`, `selector`), so a managed target accepts manager-driven calls without any target-side flag.
    function canCall(address caller, address target, bytes4 selector)
        internal
        view
        returns (bool immediate, uint32 delay)
    {
        AccessManagerStorage storage $ = accessManagerStorage();
        if ($._targets[target].closed) return (false, 0);
        if (caller == address(this)) return ($._executionId == _hashExecutionId(target, selector), 0);
        uint64 roleId = $._targets[target].allowedRoles[selector];
        if (roleId == PUBLIC_ROLE) return (true, 0);
        (bool isMember, uint32 executionDelay) = hasRole(roleId, caller);
        if (!isMember) return (false, 0);
        if (executionDelay == 0) return (true, 0);
        return (false, executionDelay);
    }

    /// @notice Returns the timestamp at which `operationId` becomes (or became) executable.
    /// @dev Returns 0 in three distinct cases:
    ///      1. The operation was never scheduled (`getNonce(operationId) == 0`).
    ///      2. The operation was consumed (executed successfully).
    ///      3. The operation was scheduled but has since expired (`readyAt + EXPIRATION <= now`).
    ///      Callers that need to distinguish case 1 from cases 2/3 should additionally call
    ///      `getNonce(operationId)`: a non-zero nonce means the operation existed at some point.
    function getSchedule(bytes32 operationId) internal view returns (uint48) {
        uint48 r = accessManagerStorage()._operationQueue.readyAt(operationId);
        if (r != 0 && _isExpired(r)) return 0;
        return r;
    }

    function getNonce(bytes32 operationId) internal view returns (uint32) {
        return accessManagerStorage()._nonces[operationId];
    }

    // ---- Role management ----

    function grantRole(uint64 roleId, address account, uint32 executionDelay) internal {
        _checkAuthorized();
        if (roleId == ADMIN_ROLE || roleId == PUBLIC_ROLE) {
            revert IAccessManager.AccessManagerLockedRole(roleId);
        }
        _grantRoleInternal(roleId, account, executionDelay);
    }

    function revokeRole(uint64 roleId, address account) internal {
        _checkAuthorized();
        if (roleId == ADMIN_ROLE || roleId == PUBLIC_ROLE) {
            revert IAccessManager.AccessManagerLockedRole(roleId);
        }
        _revokeRoleInternal(roleId, account);
    }

    function renounceRole(uint64 roleId, address callerConfirmation) internal {
        if (callerConfirmation != msg.sender) {
            revert IAccessManager.AccessManagerBadConfirmation();
        }
        if (roleId == ADMIN_ROLE || roleId == PUBLIC_ROLE) {
            revert IAccessManager.AccessManagerLockedRole(roleId);
        }
        _revokeRoleInternal(roleId, callerConfirmation);
    }

    function setRoleAdmin(uint64 roleId, uint64 admin) internal {
        _checkAuthorized();
        if (roleId == ADMIN_ROLE || roleId == PUBLIC_ROLE) {
            revert IAccessManager.AccessManagerLockedRole(roleId);
        }
        accessManagerStorage()._roles[roleId].admin = admin;
        emit IAccessManager.RoleAdminChanged(roleId, admin);
    }

    function setRoleGuardian(uint64 roleId, uint64 guardian) internal {
        _checkAuthorized();
        if (roleId == ADMIN_ROLE || roleId == PUBLIC_ROLE) {
            revert IAccessManager.AccessManagerLockedRole(roleId);
        }
        accessManagerStorage()._roles[roleId].guardian = guardian;
        emit IAccessManager.RoleGuardianChanged(roleId, guardian);
    }

    function setGrantDelay(uint64 roleId, uint32 newDelay) internal {
        _checkAuthorized();
        if (roleId == ADMIN_ROLE || roleId == PUBLIC_ROLE) {
            revert IAccessManager.AccessManagerLockedRole(roleId);
        }
        Role storage r = accessManagerStorage()._roles[roleId];
        // Consolidate any pending delay that has already become effective.
        if (r.grantDelayEffectAt != 0 && block.timestamp >= r.grantDelayEffectAt) {
            r.grantDelay = r.pendingGrantDelay;
            r.pendingGrantDelay = 0;
            r.grantDelayEffectAt = 0;
        }
        // The new value replaces any pending one, so re-setting the delay in force cancels a pending change.
        uint48 effectAt = _updateEffectAt(r.grantDelay, newDelay, MIN_SETBACK);
        r.pendingGrantDelay = newDelay;
        r.grantDelayEffectAt = effectAt;
        emit IAccessManager.RoleGrantDelayChanged(roleId, newDelay, effectAt);
    }

    function labelRole(uint64 roleId, string calldata label) internal {
        _checkAuthorized();
        if (roleId == ADMIN_ROLE || roleId == PUBLIC_ROLE) {
            revert IAccessManager.AccessManagerLockedRole(roleId);
        }
        emit IAccessManager.RoleLabel(roleId, label);
    }

    function setTargetFunctionRole(address target, bytes4[] calldata selectors, uint64 roleId) internal {
        _checkAuthorized();
        AccessManagerStorage storage $ = accessManagerStorage();
        for (uint256 i; i < selectors.length; ++i) {
            $._targets[target].allowedRoles[selectors[i]] = roleId;
            emit IAccessManager.TargetFunctionRoleUpdated(target, selectors[i], roleId);
        }
    }

    function setTargetAdminDelay(address target, uint32 newDelay) internal {
        _checkAuthorized();
        TargetConfig storage t = accessManagerStorage()._targets[target];
        // Consolidate any pending delay that has already become effective.
        if (t.adminDelayEffectAt != 0 && block.timestamp >= t.adminDelayEffectAt) {
            t.adminDelay = t.pendingAdminDelay;
            t.pendingAdminDelay = 0;
            t.adminDelayEffectAt = 0;
        }
        // Every change, an equal value included, waits at least MIN_SETBACK.
        uint48 effectAt = _updateEffectAt(t.adminDelay, newDelay, MIN_SETBACK);
        t.pendingAdminDelay = newDelay;
        t.adminDelayEffectAt = effectAt;
        emit IAccessManager.TargetAdminDelayUpdated(target, newDelay, effectAt);
    }

    function setTargetClosed(address target, bool closed) internal {
        _checkAuthorized();
        accessManagerStorage()._targets[target].closed = closed;
        emit IAccessManager.TargetClosed(target, closed);
    }

    // ---- Operation scheduling ----

    function schedule(address target, bytes calldata data, uint48 when)
        internal
        returns (bytes32 operationId, uint32 nonce)
    {
        address caller = msg.sender;
        uint32 delay = _checkCanSchedule(caller, target, data);
        operationId = hashOperation(caller, target, data);
        uint48 effectiveWhen;
        (nonce, effectiveWhen) = _writeSchedule(operationId, when, delay);
        emit IAccessManager.OperationScheduled(operationId, nonce, effectiveWhen, caller, target, data);
    }

    /// @dev OZ semantics: a delayed caller spends its matured schedule, and an available schedule is spent even
    ///      when no delay is enforced any more. With nothing to spend, it emits no {IAccessManager-OperationExecuted}
    ///      and returns `0`. A call to this manager itself is checked by {_canCallSelf}.
    function execute(address target, bytes calldata data) internal returns (uint32 nonce) {
        address caller = msg.sender;
        (bool immediate, uint32 delay) = _canCallExtended(caller, target, data);
        if (!immediate && delay == 0) {
            revert IAccessManager.AccessManagerUnauthorizedAccount(caller, _requiredRole(target, data));
        }

        bytes32 operationId = hashOperation(caller, target, data);
        if (delay != 0 || getSchedule(operationId) != 0) {
            nonce = _consumeScheduledOp(operationId);
        }

        // Authorize the manager as caller for this (target, selector) only, for the duration of the call.
        // Restoring the previous id (rather than zeroing it) keeps an enclosing execute intact.
        AccessManagerStorage storage $ = accessManagerStorage();
        bytes32 executionIdBefore = $._executionId;
        $._executionId = _hashExecutionId(target, bytes4(data[0:4]));

        (bool ok, bytes memory ret) = target.call{value: msg.value}(data);

        $._executionId = executionIdBefore;

        if (!ok) {
            // Bubble up the original revert reason if the target provided one;
            // else fall back to our typed error so callers can decode it.
            if (ret.length > 0) {
                assembly ("memory-safe") {
                    revert(add(32, ret), mload(ret))
                }
            }
            revert IAccessManager.AccessManagerTargetCallFailed(target);
        }
    }

    function cancel(address caller, address target, bytes calldata data) internal returns (uint32 nonce) {
        address msgSender = msg.sender;
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
            (bool isAdmin,) = hasRole(ADMIN_ROLE, msgSender);
            if (!isGuardian && !isAdmin) revert IAccessManager.AccessManagerUnauthorizedCancel(msgSender, target);
        }

        $._operationQueue._readyAt[operationId] = 0;
        nonce = $._nonces[operationId];
        emit IAccessManager.OperationCanceled(operationId, nonce);
    }

    function consumeScheduledOp(address caller, bytes calldata data) internal {
        address target = msg.sender;
        if (IAccessManaged(target).isConsumingScheduledOp() != IAccessManaged.isConsumingScheduledOp.selector) {
            revert IAccessManager.AccessManagerUnauthorizedConsume(target);
        }
        _consumeScheduledOp(hashOperation(caller, target, data));
    }

    // ---- Managed targets ----

    /// @notice Points managed `target` at `newAuthority`. Reverts unless the caller holds `ADMIN_ROLE` (having
    ///         scheduled the call when `target` has an admin delay) and this manager is `target`'s current authority.
    /// @dev As in OZ, the admin delay binds this path only. `execute(target, setAuthority(x))` is gated by `target`'s
    ///      function role for `setAuthority`, which defaults to ADMIN_ROLE, so an admin can migrate at once that way.
    ///      For the admin delay to guard migration, map `target`'s `setAuthority` selector to a role nobody holds
    ///      ({setTargetFunctionRole}); changing that mapping back is itself held back by the admin delay.
    function updateAuthority(address target, address newAuthority) internal {
        _checkAuthorized();
        IAccessManaged(target).setAuthority(newAuthority);
    }

    // ---- Internal helpers ----

    function _hashExecutionId(address target, bytes4 selector) private pure returns (bytes32) {
        return keccak256(abi.encode(target, selector));
    }

    /// @dev Spends the scheduled `operationId`, reverting unless it is scheduled, ready and not expired.
    function _consumeScheduledOp(bytes32 operationId) private returns (uint32 nonce) {
        AccessManagerStorage storage $ = accessManagerStorage();
        uint48 readyAt = $._operationQueue._readyAt[operationId];
        if (readyAt == 0) revert IAccessManager.AccessManagerNotScheduled(operationId);
        if (block.timestamp < readyAt) revert IAccessManager.AccessManagerNotReady(operationId);
        if (_isExpired(readyAt)) revert IAccessManager.AccessManagerExpired(operationId);
        $._operationQueue._readyAt[operationId] = 0;
        nonce = $._nonces[operationId];
        emit IAccessManager.OperationExecuted(operationId, nonce);
    }

    /// @dev OZ `_isExpired`: an operation ready at `readyAt` expires at `readyAt + EXPIRATION`, that second included.
    function _isExpired(uint48 readyAt) private view returns (bool) {
        return uint256(readyAt) + EXPIRATION <= block.timestamp;
    }

    function _effectiveDelay(Delay storage d) private view returns (uint32) {
        if (d.effectAt != 0 && block.timestamp >= d.effectAt) return d.pendingValue;
        return d.value;
    }

    /// @dev OZ `Time.Delay.withUpdate`'s effect time: a change from `currentDelay` to `newDelay` waits out the
    ///      decrease (`currentDelay - newDelay`, nothing for an increase), and at least `minSetback`.
    function _updateEffectAt(uint32 currentDelay, uint32 newDelay, uint32 minSetback) private view returns (uint48) {
        uint32 diff = currentDelay > newDelay ? currentDelay - newDelay : 0;
        return uint48(block.timestamp + (diff > minSetback ? diff : minSetback));
    }

    /// @dev OZ `_grantRole`. A new member joins after the role's grant delay, and the event's `since` is that time.
    ///      An existing member keeps `since` and gets `delay.withUpdate(executionDelay, 0)`: an increase applies at
    ///      once, a decrease after the difference, and the event's `since` is when the new delay takes effect.
    ///      The new value replaces any pending one, measured from the delay in force.
    function _grantRoleInternal(uint64 roleId, address account, uint32 executionDelay) private {
        AccessManagerStorage storage $ = accessManagerStorage();
        Access storage a = $._access[roleId][account];
        bool isNewMember = a.since == 0;
        uint48 since;
        if (isNewMember) {
            since = uint48(block.timestamp) + uint48(getRoleGrantDelay(roleId));
            a.since = since;
            a.delay.value = executionDelay;
            $._roleMembers[roleId].add(account);
        } else {
            uint32 currentDelay = _effectiveDelay(a.delay);
            since = _updateEffectAt(currentDelay, executionDelay, 0);
            a.delay = Delay({value: currentDelay, pendingValue: executionDelay, effectAt: since});
        }
        emit IAccessManager.RoleGranted(roleId, account, executionDelay, since, isNewMember);
    }

    function _revokeRoleInternal(uint64 roleId, address account) private {
        AccessManagerStorage storage $ = accessManagerStorage();
        if ($._access[roleId][account].since == 0) return;
        delete $._access[roleId][account];
        $._roleMembers[roleId].remove(account);
        emit IAccessManager.RoleRevoked(roleId, account);
    }

    /// @dev OZ `onlyAuthorized`: gates this manager's own restricted functions on the current call (`msg.data`).
    ///      A caller whose required delay ({_getAdminRestrictions}) is non-zero must have scheduled this exact call
    ///      against this manager, and the matured schedule is consumed here. The manager itself passes only while
    ///      {execute} is running this selector. Only the facet entrypoint of the same name may reach a restricted
    ///      library function, so that `msg.data` is the call being authorized.
    function _checkAuthorized() private {
        address caller = msg.sender;
        (bool immediate, uint32 delay) = _canCallSelf(caller, msg.data);
        if (immediate) return;
        if (delay == 0) {
            (, uint64 roleId,) = _getAdminRestrictions(msg.data);
            revert IAccessManager.AccessManagerUnauthorizedAccount(caller, roleId);
        }
        _consumeScheduledOp(hashOperation(caller, address(this), msg.data));
    }

    /// @dev OZ `_getAdminRestrictions`: whether `data` calls one of this manager's restricted functions, the role
    ///      that may call it, and the operation delay it carries on top of the caller's execution delay. Target
    ///      configuration and `updateAuthority` carry the target's admin delay; `grantRole` and `revokeRole` are
    ///      restricted to the role's admin. Any other selector falls back to this contract's own target roles.
    function _getAdminRestrictions(bytes calldata data)
        private
        view
        returns (bool adminRestricted, uint64 roleId, uint32 operationDelay)
    {
        if (data.length < 4) return (false, 0, 0);
        bytes4 selector = bytes4(data[0:4]);

        if (
            selector == IAccessManager.labelRole.selector || selector == IAccessManager.setRoleAdmin.selector
                || selector == IAccessManager.setRoleGuardian.selector
                || selector == IAccessManager.setGrantDelay.selector
                || selector == IAccessManager.setTargetAdminDelay.selector
        ) {
            return (true, ADMIN_ROLE, 0);
        }

        if (
            selector == IAccessManager.updateAuthority.selector || selector == IAccessManager.setTargetClosed.selector
                || selector == IAccessManager.setTargetFunctionRole.selector
        ) {
            // The first argument is the target.
            address target = abi.decode(data[4:36], (address));
            return (true, ADMIN_ROLE, getTargetAdminDelay(target));
        }

        if (selector == IAccessManager.grantRole.selector || selector == IAccessManager.revokeRole.selector) {
            // The first argument is the role.
            uint64 role = abi.decode(data[4:36], (uint64));
            return (true, getRoleAdmin(role), 0);
        }

        return (false, getTargetFunctionRole(address(this), selector), 0);
    }

    /// @dev OZ `_canCallExtended`: {canCall}, except that a call to this manager is checked by {_canCallSelf}.
    function _canCallExtended(address caller, address target, bytes calldata data)
        private
        view
        returns (bool immediate, uint32 delay)
    {
        if (target == address(this)) return _canCallSelf(caller, data);
        if (data.length < 4) return (false, 0);
        return canCall(caller, target, bytes4(data[0:4]));
    }

    /// @dev OZ `_canCallSelf`: {canCall} for a call to this manager, applying {_getAdminRestrictions}. The closed
    ///      flag binds only selectors that are not admin-restricted, and the required delay is the larger of the
    ///      operation delay and the caller's execution delay.
    function _canCallSelf(address caller, bytes calldata data) private view returns (bool immediate, uint32 delay) {
        if (data.length < 4) return (false, 0);
        if (caller == address(this)) {
            // Sent through {execute}, which already checked the original caller: accept only the call in flight.
            return (accessManagerStorage()._executionId == _hashExecutionId(address(this), bytes4(data[0:4])), 0);
        }

        (bool adminRestricted, uint64 roleId, uint32 operationDelay) = _getAdminRestrictions(data);
        if (!adminRestricted && isTargetClosed(address(this))) return (false, 0);

        (bool inRole, uint32 executionDelay) = hasRole(roleId, caller);
        if (!inRole) return (false, 0);

        delay = operationDelay > executionDelay ? operationDelay : executionDelay;
        immediate = delay == 0;
    }

    /// @dev The role reported when `caller` may not call `data` on `target` at all.
    function _requiredRole(address target, bytes calldata data) private view returns (uint64 roleId) {
        if (target == address(this)) {
            (, roleId,) = _getAdminRestrictions(data);
        } else {
            roleId = getTargetFunctionRole(target, bytes4(data[0:4]));
        }
    }

    /// @dev Validates that `caller` may schedule a call to `target` with `data` and returns
    ///      the required execution delay. Reverts if the caller has no access at all or has
    ///      immediate access (no schedule needed).
    function _checkCanSchedule(address caller, address target, bytes calldata data)
        private
        view
        returns (uint32 delay)
    {
        (bool immediate, uint32 d) = _canCallExtended(caller, target, data);
        if (!immediate && d == 0) {
            revert IAccessManager.AccessManagerUnauthorizedAccount(caller, _requiredRole(target, data));
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
        uint48 existing = $._operationQueue._readyAt[operationId];
        if (existing != 0) {
            if (!_isExpired(existing)) revert IAccessManager.AccessManagerAlreadyScheduled(operationId);
            // If expired, clear and allow reschedule
            $._operationQueue._readyAt[operationId] = 0;
        }
        uint48 minWhen = uint48(block.timestamp) + delay;
        effectiveWhen = when < minWhen ? minWhen : when;
        $._operationQueue._readyAt[operationId] = effectiveWhen;
        nonce = ++$._nextNonce;
        $._nonces[operationId] = nonce;
    }
}
