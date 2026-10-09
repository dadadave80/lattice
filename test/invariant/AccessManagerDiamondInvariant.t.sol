// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessManagedTestBase} from "@lattice-test/base/AccessManagedTestBase.sol";
import {AccessManagedTestFacet} from "@lattice-test/helpers/AccessManagedTestFacet.sol";
import {AccessManager} from "@lattice/access/AccessManager.sol";
import {IAccessManaged} from "@lattice/interfaces/access/IAccessManaged.sol";
import {IAccessManager} from "@lattice/interfaces/access/IAccessManager.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                 FIXTURES
//////////////////////////////////////////////////////////////////////////*//

/// @notice Plain call target: counts the calls that reach it. Only the manager's `execute` calls it.
contract InvCallSink {
    uint256 public hits;

    function ping() external {
        ++hits;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                  HANDLER
//////////////////////////////////////////////////////////////////////////*//

/// @notice Drives a recipe-built AccessManager diamond and a recipe-built AccessManaged diamond: role grants
///         (new members and #299 re-grants), revokes, renounces, role admin/guardian and grant-delay changes,
///         target role and closed changes, and the operation lifecycle (schedule, execute, direct consumption by
///         the managed target or by the manager's own restricted functions, cancel), with time warps between.
/// @dev Every expected outcome comes from an independent ghost model of Lattice's AccessManager semantics, never
///      from the manager's own views. The model follows OpenZeppelin v5.6.1 (`Time.Delay.withUpdate`/`getFull`,
///      `_grantRole`, `_canCallExtended`, `_consumeScheduledOp`) with the differences that {IAccessManager}'s
///      dev notes list: ADMIN_ROLE cannot be granted, revoked or renounced; nonces come from one global counter;
///      `schedule` raises a too-early `when` instead of reverting, and refuses an immediate caller with
///      `AccessManagerNotScheduled`; errors keep the Lattice shapes (`AccessManagerUnauthorizedAccount`, the
///      two-argument `AccessManagerUnauthorizedCancel`); and `hasRole` reports delay 0 before a grant takes
///      effect. It does not claim OZ v5.6.1 parity. Under `fail_on_revert` an authorised call must succeed and any
///      other call must revert with the exact error the model predicts (`vm.expectRevert`), so a divergence fails
///      the run.
///      Out of scope: target admin delays (`setTargetAdminDelay`), `updateAuthority` and `labelRole`.
contract AccessManagerHandler is Test {
    struct GhostAccess {
        uint48 since;
        uint32 value;
        uint32 pendingValue;
        uint48 effectAt;
    }

    struct GhostDelay {
        uint32 value;
        uint32 pendingValue;
        uint48 effectAt;
    }

    struct GhostOp {
        address caller;
        uint8 kind;
        uint8 accountIdx;
        uint8 delayIdx;
    }

    uint64 public constant ADMIN_ROLE = 0;
    uint64 public constant PUBLIC_ROLE = type(uint64).max;
    uint64 public constant R1 = 1;
    uint64 public constant R2 = 2;
    uint64 public constant R3 = 3;
    uint32 internal constant MIN_SETBACK = 5 days;
    uint32 internal constant EXPIRATION = 1 weeks;

    /// @dev Operation kinds: a call to the plain sink, a call to the managed target's restricted function, and
    ///      the manager's own `grantRole(R2, …)` / `revokeRole(R2, …)` (authorised by R2's admin role).
    uint8 internal constant OP_PING = 0;
    uint8 internal constant OP_MANAGED = 1;
    uint8 internal constant OP_GRANT = 2;
    uint8 internal constant OP_REVOKE = 3;

    AccessManager public immutable mgr;
    address public immutable managed;
    InvCallSink public immutable sink;
    address public immutable ADMIN;

    address[5] internal _actors;
    uint64[4] internal _roles;
    uint32[3] internal _opDelays;

    mapping(uint64 role => mapping(address account => GhostAccess)) internal _access;
    mapping(uint64 role => uint256) public ghostMemberCount;
    mapping(uint64 role => uint64) public ghostRoleAdmin;
    mapping(uint64 role => uint64) public ghostRoleGuardian;
    mapping(uint64 role => GhostDelay) internal _grantDelay;
    mapping(address target => uint64) public ghostTargetRole;
    mapping(address target => bool) public ghostClosed;

    /// @dev Raw stored `readyAt` (0 once consumed or cancelled; kept after expiry, as the manager keeps it).
    mapping(bytes32 opId => uint48) public ghostReadyAt;
    mapping(bytes32 opId => uint32) public ghostNonce;
    mapping(bytes32 opId => bool) internal _tracked;
    bytes32[] public opIds;
    GhostOp[] internal _ops;
    uint32 public ghostNextNonce;

    uint256 public ghostSinkHits;

    constructor(AccessManager mgr_, address managed_, InvCallSink sink_, address admin_) {
        mgr = mgr_;
        managed = managed_;
        sink = sink_;
        ADMIN = admin_;

        _actors[0] = admin_;
        _actors[1] = address(0xE1);
        _actors[2] = address(0xE2);
        _actors[3] = address(0xE3);
        _actors[4] = address(0xE4);

        _roles[0] = ADMIN_ROLE;
        _roles[1] = R1;
        _roles[2] = R2;
        _roles[3] = R3;

        _opDelays[0] = 0;
        _opDelays[1] = 1 hours;
        _opDelays[2] = 2 days;

        _access[ADMIN_ROLE][admin_].since = uint48(block.timestamp);
        ghostMemberCount[ADMIN_ROLE] = 1;
    }

    /// @notice The configuration `setUp` applies through the admin, mirrored into the model.
    function configure() external {
        vm.startPrank(ADMIN);
        // Seed immediate and delayed members so the scheduled paths are live from the first call.
        _seedGrant(R1, _actors[1], 0);
        _seedGrant(R2, _actors[2], 1 hours);
        _seedGrant(R1, _actors[3], 1 days);
        _seedGrant(R3, _actors[4], 0);

        mgr.setRoleAdmin(R2, R1);
        mgr.setRoleGuardian(R1, R3);
        bytes4[] memory ping = new bytes4[](1);
        ping[0] = InvCallSink.ping.selector;
        mgr.setTargetFunctionRole(address(sink), ping, R1);
        bytes4[] memory restricted = new bytes4[](1);
        restricted[0] = AccessManagedTestFacet.restrictedFn.selector;
        mgr.setTargetFunctionRole(managed, restricted, R2);
        ghostRoleAdmin[R2] = R1;
        ghostRoleGuardian[R1] = R3;
        ghostTargetRole[address(sink)] = R1;
        ghostTargetRole[managed] = R2;
        vm.stopPrank();
    }

    function _seedGrant(uint64 role, address account, uint32 executionDelay) internal {
        mgr.grantRole(role, account, executionDelay);
        _modelGrant(role, account, executionDelay);
    }

    // ---- Views for the invariants ----

    function actors() external view returns (address[5] memory) {
        return _actors;
    }

    function roles() external view returns (uint64[4] memory) {
        return _roles;
    }

    function opCount() external view returns (uint256) {
        return opIds.length;
    }

    /// @notice OZ `hasRole`, with Lattice's documented difference: a not-yet-effective member reports delay 0.
    function modelHasRole(uint64 role, address account) public view returns (bool isMember, uint32 delay) {
        if (role == PUBLIC_ROLE) return (true, 0);
        GhostAccess memory a = _access[role][account];
        isMember = a.since != 0 && block.timestamp >= a.since;
        if (isMember) delay = _get(a.value, a.pendingValue, a.effectAt);
    }

    /// @notice OZ `getAccess` (`Delay.getFull`).
    function modelGetAccess(uint64 role, address account)
        public
        view
        returns (uint48 since, uint32 current, uint32 pending, uint48 effect)
    {
        GhostAccess memory a = _access[role][account];
        since = a.since;
        if (a.effectAt != 0 && block.timestamp >= a.effectAt) return (since, a.pendingValue, 0, 0);
        return (since, a.value, a.pendingValue, a.effectAt);
    }

    function modelGrantDelay(uint64 role) public view returns (uint32) {
        GhostDelay memory d = _grantDelay[role];
        return _get(d.value, d.pendingValue, d.effectAt);
    }

    function isGranted(uint64 role, address account) external view returns (bool) {
        return _access[role][account].since != 0;
    }

    /// @notice OZ `canCall` for an outside caller on a plain target.
    function modelCanCall(address caller, address target) public view returns (bool immediate, uint32 delay) {
        if (ghostClosed[target]) return (false, 0);
        uint64 role = ghostTargetRole[target];
        if (role == PUBLIC_ROLE) return (true, 0);
        (bool isMember, uint32 d) = modelHasRole(role, caller);
        if (!isMember) return (false, 0);
        return d == 0 ? (true, uint32(0)) : (false, d);
    }

    /// @notice OZ `getSchedule`: 0 once expired.
    function modelGetSchedule(bytes32 opId) public view returns (uint48) {
        uint48 r = ghostReadyAt[opId];
        return r != 0 && _isExpired(r) ? 0 : r;
    }

    // ---- Model internals ----

    function _get(uint32 value, uint32 pending, uint48 effectAt) internal view returns (uint32) {
        return effectAt != 0 && block.timestamp >= effectAt ? pending : value;
    }

    function _isExpired(uint48 readyAt) internal view returns (bool) {
        return uint256(readyAt) + EXPIRATION <= block.timestamp;
    }

    function _setback(uint32 current, uint32 next, uint32 minSetback) internal view returns (uint48) {
        uint32 diff = current > next ? current - next : 0;
        return uint48(block.timestamp + (diff > minSetback ? diff : minSetback));
    }

    /// @dev OZ `_grantRole`: a new member joins after the grant delay; an existing one gets
    ///      `delay.withUpdate(executionDelay, 0)`.
    function _modelGrant(uint64 role, address account, uint32 executionDelay) internal {
        GhostAccess storage a = _access[role][account];
        if (a.since == 0) {
            a.since = uint48(block.timestamp) + modelGrantDelay(role);
            a.value = executionDelay;
            ++ghostMemberCount[role];
        } else {
            uint32 current = _get(a.value, a.pendingValue, a.effectAt);
            a.value = current;
            a.pendingValue = executionDelay;
            a.effectAt = _setback(current, executionDelay, 0);
        }
    }

    function _modelRevoke(uint64 role, address account) internal {
        if (_access[role][account].since == 0) return;
        delete _access[role][account];
        --ghostMemberCount[role];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return _actors[seed % _actors.length];
    }

    function _role(uint256 seed) internal pure returns (uint64) {
        return uint64(seed % 3) + 1;
    }

    /// @dev Even seeds pick a granted holder of `role` when one exists, so authorised paths run often.
    function _callerFor(uint64 role, uint256 seed) internal view returns (address) {
        if (seed % 2 == 0) {
            for (uint256 i; i < _actors.length; ++i) {
                address candidate = _actors[(seed / 2 % _actors.length + i) % _actors.length];
                if (_access[role][candidate].since != 0) return candidate;
            }
        }
        return _actor(seed / 2);
    }

    // ---- Operations ----

    function _target(GhostOp memory op) internal view returns (address) {
        if (op.kind == OP_PING) return address(sink);
        if (op.kind == OP_MANAGED) return managed;
        return address(mgr);
    }

    function _data(GhostOp memory op) internal view returns (bytes memory) {
        if (op.kind == OP_PING) return abi.encodeCall(InvCallSink.ping, ());
        if (op.kind == OP_MANAGED) return abi.encodeCall(AccessManagedTestFacet.restrictedFn, ());
        if (op.kind == OP_GRANT) {
            return abi.encodeCall(IAccessManager.grantRole, (R2, _actors[op.accountIdx], _opDelays[op.delayIdx]));
        }
        return abi.encodeCall(IAccessManager.revokeRole, (R2, _actors[op.accountIdx]));
    }

    function _opId(GhostOp memory op) internal view returns (bytes32) {
        return keccak256(abi.encode(op.caller, _target(op), _data(op)));
    }

    /// @dev `_canCallExtended` for `op`, and the role reported when the caller has no access at all.
    function _modelCanCallOp(GhostOp memory op) internal view returns (bool immediate, uint32 delay, uint64 role) {
        if (op.kind == OP_GRANT || op.kind == OP_REVOKE) {
            role = ghostRoleAdmin[R2];
            (bool isMember, uint32 d) = modelHasRole(role, op.caller);
            if (!isMember) return (false, 0, role);
            return (d == 0, d, role);
        }
        address target = _target(op);
        role = ghostTargetRole[target];
        (immediate, delay) = modelCanCall(op.caller, target);
    }

    /// @dev Applies `op`'s effect once its call succeeds.
    function _applyOp(GhostOp memory op) internal {
        if (op.kind == OP_PING) ++ghostSinkHits;
        else if (op.kind == OP_GRANT) _modelGrant(R2, _actors[op.accountIdx], _opDelays[op.delayIdx]);
        else if (op.kind == OP_REVOKE) _modelRevoke(R2, _actors[op.accountIdx]);
    }

    /// @dev OZ `_consumeScheduledOp`: arms the predicted revert and returns false, or returns true (the caller then
    ///      marks the op consumed once its call succeeds).
    function _expectConsume(bytes32 opId) internal returns (bool ok) {
        uint48 r = ghostReadyAt[opId];
        if (r == 0) {
            vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, opId));
        } else if (block.timestamp < r) {
            vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotReady.selector, opId));
        } else if (_isExpired(r)) {
            vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerExpired.selector, opId));
        } else {
            return true;
        }
    }

    function _consume(bytes32 opId) internal {
        ghostReadyAt[opId] = 0;
    }

    /// @dev Half the time replays a tracked operation, preferring one still scheduled, so schedule → warp →
    ///      execute sequences line up. A fresh operation's caller is, on even seeds, a member of the role it
    ///      needs, preferring one whose execution delay forces a schedule.
    function _pickOp(uint256 seed, uint256 callerSeed, uint256 kindSeed) internal view returns (GhostOp memory op) {
        uint256 n = _ops.length;
        if (seed % 2 == 0 && n > 0) {
            uint256 start = (seed / 2) % n;
            for (uint256 i; i < n; ++i) {
                if (ghostReadyAt[opIds[(start + i) % n]] != 0) return _ops[(start + i) % n];
            }
            return _ops[start];
        }
        op.kind = uint8(kindSeed % 4);
        op.accountIdx = uint8((kindSeed / 4) % _actors.length);
        op.delayIdx = uint8((kindSeed / 32) % _opDelays.length);
        uint64 role = op.kind == OP_PING
            ? ghostTargetRole[address(sink)]
            : op.kind == OP_MANAGED ? ghostTargetRole[managed] : ghostRoleAdmin[R2];
        op.caller = _callerFor(role, callerSeed);
        if (callerSeed % 2 == 0) {
            for (uint256 i; i < _actors.length; ++i) {
                (bool isMember, uint32 d) = modelHasRole(role, _actors[i]);
                if (isMember && d > 0) {
                    op.caller = _actors[i];
                    break;
                }
            }
        }
    }

    function _track(GhostOp memory op, bytes32 opId) internal {
        if (_tracked[opId]) return;
        _tracked[opId] = true;
        opIds.push(opId);
        _ops.push(op);
    }

    // ---- Time ----

    /// @notice Moves time forward up to 4 days; one call in eight jumps 8 days, past the 1-week expiration.
    function warp(uint256 secs) external {
        vm.warp(block.timestamp + (secs % 8 == 0 ? 8 days : bound(secs, 1, 4 days)));
    }

    // ---- Role management ----

    /// @notice grantRole on R1–R3 (an eighth of calls try the locked ADMIN/PUBLIC roles). The caller needs the
    ///         role's admin role; a caller whose admin membership carries an execution delay must consume a
    ///         matured schedule of this exact call.
    function grantRole(uint256 callerSeed, uint256 roleSeed, uint256 accountSeed, uint256 delaySeed) external {
        uint64 role = roleSeed % 8 == 0 ? (roleSeed % 16 == 0 ? ADMIN_ROLE : PUBLIC_ROLE) : _role(roleSeed);
        uint64 adminRole = ghostRoleAdmin[role];
        address caller = _callerFor(adminRole, callerSeed);
        address account = _actor(accountSeed);
        uint32 executionDelay = uint32(bound(delaySeed, 0, 3 days));
        bytes memory data = abi.encodeCall(IAccessManager.grantRole, (role, account, executionDelay));
        bytes32 opId = keccak256(abi.encode(caller, address(mgr), data));

        if (_expectAuthorized(caller, adminRole, opId)) {
            if (role == ADMIN_ROLE || role == PUBLIC_ROLE) {
                vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerLockedRole.selector, role));
                vm.prank(caller);
                mgr.grantRole(role, account, executionDelay);
                return;
            }
            vm.prank(caller);
            mgr.grantRole(role, account, executionDelay);
            _modelGrant(role, account, executionDelay);
            return;
        }
        vm.prank(caller);
        mgr.grantRole(role, account, executionDelay);
    }

    function revokeRole(uint256 callerSeed, uint256 roleSeed, uint256 accountSeed) external {
        uint64 role = roleSeed % 8 == 0 ? ADMIN_ROLE : _role(roleSeed);
        uint64 adminRole = ghostRoleAdmin[role];
        address caller = _callerFor(adminRole, callerSeed);
        address account = _actor(accountSeed);
        bytes memory data = abi.encodeCall(IAccessManager.revokeRole, (role, account));
        bytes32 opId = keccak256(abi.encode(caller, address(mgr), data));

        if (_expectAuthorized(caller, adminRole, opId)) {
            if (role == ADMIN_ROLE) {
                vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerLockedRole.selector, role));
                vm.prank(caller);
                mgr.revokeRole(role, account);
                return;
            }
            vm.prank(caller);
            mgr.revokeRole(role, account);
            _modelRevoke(role, account);
            return;
        }
        vm.prank(caller);
        mgr.revokeRole(role, account);
    }

    /// @dev `_checkAuthorized` on a role-admin-restricted call: true when the call passes (consuming a matured
    ///      schedule if the caller's admin membership carries a delay); otherwise arms the predicted revert.
    function _expectAuthorized(address caller, uint64 adminRole, bytes32 opId) internal returns (bool) {
        (bool isMember, uint32 d) = modelHasRole(adminRole, caller);
        if (!isMember) {
            vm.expectRevert(
                abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedAccount.selector, caller, adminRole)
            );
            return false;
        }
        if (d == 0) return true;
        if (!_expectConsume(opId)) return false;
        _consume(opId);
        return true;
    }

    function renounceRole(uint256 callerSeed, uint256 roleSeed, uint256 confirmationSeed) external {
        uint64 role = roleSeed % 8 == 0 ? ADMIN_ROLE : _role(roleSeed);
        address caller = _callerFor(role, callerSeed);
        if (confirmationSeed % 4 == 0) {
            address wrong = _actors[(callerSeed / 2 % _actors.length + 1) % _actors.length];
            if (wrong == caller) wrong = _actors[(callerSeed / 2 % _actors.length + 2) % _actors.length];
            vm.expectRevert(IAccessManager.AccessManagerBadConfirmation.selector);
            vm.prank(caller);
            mgr.renounceRole(role, wrong);
            return;
        }
        if (role == ADMIN_ROLE) {
            vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerLockedRole.selector, role));
            vm.prank(caller);
            mgr.renounceRole(role, caller);
            return;
        }
        vm.prank(caller);
        mgr.renounceRole(role, caller);
        _modelRevoke(role, caller);
    }

    /// @dev Admin-only configuration: the admin passes at once (its own delay is always 0); anyone else is refused.
    function _adminOrExpectRevert(uint256 callerSeed) internal returns (address caller, bool authorized) {
        caller = callerSeed % 4 == 0 ? _actor(callerSeed / 4) : ADMIN;
        (bool isMember, uint32 d) = modelHasRole(ADMIN_ROLE, caller);
        authorized = isMember && d == 0;
        if (!authorized) {
            vm.expectRevert(
                abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedAccount.selector, caller, ADMIN_ROLE)
            );
        }
    }

    function setRoleAdmin(uint256 callerSeed, uint256 roleSeed, uint256 adminSeed) external {
        uint64 role = _role(roleSeed);
        uint64 admin = _roles[adminSeed % _roles.length];
        (address caller, bool authorized) = _adminOrExpectRevert(callerSeed);
        vm.prank(caller);
        mgr.setRoleAdmin(role, admin);
        if (authorized) ghostRoleAdmin[role] = admin;
    }

    function setRoleGuardian(uint256 callerSeed, uint256 roleSeed, uint256 guardianSeed) external {
        uint64 role = _role(roleSeed);
        uint64 guardian = _roles[guardianSeed % _roles.length];
        (address caller, bool authorized) = _adminOrExpectRevert(callerSeed);
        vm.prank(caller);
        mgr.setRoleGuardian(role, guardian);
        if (authorized) ghostRoleGuardian[role] = guardian;
    }

    /// @notice OZ `_setGrantDelay`: `withUpdate(newDelay, minSetback())` from the delay in force.
    function setGrantDelay(uint256 callerSeed, uint256 roleSeed, uint256 delaySeed) external {
        uint64 role = _role(roleSeed);
        uint32 newDelay = uint32(bound(delaySeed, 0, 10 days));
        (address caller, bool authorized) = _adminOrExpectRevert(callerSeed);
        vm.prank(caller);
        mgr.setGrantDelay(role, newDelay);
        if (authorized) {
            GhostDelay storage g = _grantDelay[role];
            uint32 current = _get(g.value, g.pendingValue, g.effectAt);
            g.effectAt = _setback(current, newDelay, MIN_SETBACK);
            g.value = current;
            g.pendingValue = newDelay;
        }
    }

    function setTargetFunctionRole(uint256 callerSeed, uint256 targetSeed, uint256 roleSeed) external {
        address target = targetSeed % 2 == 0 ? address(sink) : managed;
        uint64 role = roleSeed % 4 == 0 ? PUBLIC_ROLE : _role(roleSeed);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] =
            target == address(sink) ? InvCallSink.ping.selector : AccessManagedTestFacet.restrictedFn.selector;
        (address caller, bool authorized) = _adminOrExpectRevert(callerSeed);
        vm.prank(caller);
        mgr.setTargetFunctionRole(target, selectors, role);
        if (authorized) ghostTargetRole[target] = role;
    }

    function setTargetClosed(uint256 callerSeed, uint256 targetSeed, bool closed) external {
        address target = targetSeed % 2 == 0 ? address(sink) : managed;
        (address caller, bool authorized) = _adminOrExpectRevert(callerSeed);
        vm.prank(caller);
        mgr.setTargetClosed(target, closed);
        if (authorized) ghostClosed[target] = closed;
    }

    // ---- Operation lifecycle ----

    function schedule(uint256 opSeed, uint256 callerSeed, uint256 kindSeed, uint256 whenSeed) external {
        GhostOp memory op = _pickOp(opSeed, callerSeed, kindSeed);
        address target = _target(op);
        bytes memory data = _data(op);
        bytes32 opId = _opId(op);
        uint48 when = uint48(bound(whenSeed, 0, block.timestamp + 3 days));
        (bool immediate, uint32 delay, uint64 role) = _modelCanCallOp(op);

        if (!immediate && delay == 0) {
            vm.expectRevert(
                abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedAccount.selector, op.caller, role)
            );
        } else if (immediate) {
            vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, opId));
        } else if (ghostReadyAt[opId] != 0 && !_isExpired(ghostReadyAt[opId])) {
            vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerAlreadyScheduled.selector, opId));
        } else {
            vm.prank(op.caller);
            (bytes32 id, uint32 nonce) = mgr.schedule(target, data, when);
            assertEq(id, opId, "operation id");
            uint48 minWhen = uint48(block.timestamp) + delay;
            ghostReadyAt[opId] = when < minWhen ? minWhen : when;
            ghostNonce[opId] = ++ghostNextNonce;
            assertEq(nonce, ghostNextNonce, "nonce");
            _track(op, opId);
            return;
        }
        vm.prank(op.caller);
        mgr.schedule(target, data, when);
    }

    /// @notice OZ `execute`: a delayed caller spends its matured schedule, and a live schedule is spent even when
    ///         the call is immediate.
    function execute(uint256 opSeed, uint256 callerSeed, uint256 kindSeed) external {
        GhostOp memory op = _pickOp(opSeed, callerSeed, kindSeed);
        address target = _target(op);
        bytes memory data = _data(op);
        bytes32 opId = _opId(op);
        (bool immediate, uint32 delay, uint64 role) = _modelCanCallOp(op);

        if (!immediate && delay == 0) {
            vm.expectRevert(
                abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedAccount.selector, op.caller, role)
            );
            vm.prank(op.caller);
            mgr.execute(target, data);
            return;
        }
        bool consumes = delay != 0 || modelGetSchedule(opId) != 0;
        if (consumes && !_expectConsume(opId)) {
            vm.prank(op.caller);
            mgr.execute(target, data);
            return;
        }
        vm.prank(op.caller);
        uint32 nonce = mgr.execute(target, data);
        if (consumes) {
            assertEq(nonce, ghostNonce[opId], "execute nonce");
            _consume(opId);
        } else {
            assertEq(nonce, 0, "unscheduled execute nonce");
        }
        _applyOp(op);
        (bool selfImmediate,) = mgr.canCall(address(mgr), target, bytes4(data));
        assertFalse(selfImmediate, "execution id left set after execute");
    }

    /// @notice Replays a tracked operation as a direct call: the managed target consumes it through
    ///         `consumeScheduledOp`, and the manager's own `grantRole`/`revokeRole` through `_checkAuthorized`.
    ///         An immediate caller passes without consuming.
    function directCall(uint256 opSeed, uint256 callerSeed, uint256 kindSeed) external {
        GhostOp memory op = _pickOp(opSeed, callerSeed, kindSeed);
        if (op.kind == OP_PING) return;
        bytes32 opId = _opId(op);
        (bool immediate, uint32 delay, uint64 role) = _modelCanCallOp(op);

        bool ok = true;
        bool consumes;
        if (!immediate && delay == 0) {
            ok = false;
            if (op.kind == OP_MANAGED) {
                vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, op.caller));
            } else {
                vm.expectRevert(
                    abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedAccount.selector, op.caller, role)
                );
            }
        } else if (!immediate) {
            consumes = true;
            ok = _expectConsume(opId);
        }

        vm.prank(op.caller);
        if (op.kind == OP_MANAGED) {
            AccessManagedTestFacet(managed).restrictedFn();
        } else if (op.kind == OP_GRANT) {
            mgr.grantRole(R2, _actors[op.accountIdx], _opDelays[op.delayIdx]);
        } else {
            mgr.revokeRole(R2, _actors[op.accountIdx]);
        }
        if (!ok) return;
        if (consumes) _consume(opId);
        _applyOp(op);
        if (op.kind == OP_MANAGED) {
            assertEq(IAccessManaged(managed).isConsumingScheduledOp(), bytes4(0), "consuming flag left set");
        }
    }

    /// @notice Cancel by the scheduler, the role's guardian or an admin; anyone else is refused.
    function cancel(uint256 opSeed, uint256 cancellerSeed) external {
        if (_ops.length == 0) return;
        GhostOp memory op = _ops[opSeed % _ops.length];
        address target = _target(op);
        bytes memory data = _data(op);
        bytes32 opId = _opId(op);
        address canceller = cancellerSeed % 3 == 0 ? op.caller : _actor(cancellerSeed);

        if (ghostReadyAt[opId] == 0) {
            vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, opId));
            vm.prank(canceller);
            mgr.cancel(op.caller, target, data);
            return;
        }
        if (canceller != op.caller) {
            // The manager's own functions have no target role set, so they map to ADMIN_ROLE.
            uint64 role = target == address(mgr) ? ADMIN_ROLE : ghostTargetRole[target];
            uint64 guardian = role == ADMIN_ROLE || role == PUBLIC_ROLE ? ADMIN_ROLE : ghostRoleGuardian[role];
            (bool isGuardian,) = modelHasRole(guardian, canceller);
            (bool isAdmin,) = modelHasRole(ADMIN_ROLE, canceller);
            if (!isGuardian && !isAdmin) {
                vm.expectRevert(
                    abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedCancel.selector, canceller, target)
                );
                vm.prank(canceller);
                mgr.cancel(op.caller, target, data);
                return;
            }
        }
        vm.prank(canceller);
        uint32 nonce = mgr.cancel(op.caller, target, data);
        assertEq(nonce, ghostNonce[opId], "cancel nonce");
        ghostReadyAt[opId] = 0;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                               INVARIANT TEST
//////////////////////////////////////////////////////////////////////////*//

/// @title AccessManagerDiamondInvariant
/// @notice Stateful properties of a {DeployAccessManager} diamond governing a {DeployAccessManaged} diamond and a
///         plain target (#231 Phase 2):
///         - role membership, execution delays (including #299's pending decreases) and `getAccess` always equal
///           an independent model of Lattice's AccessManager semantics (OZ v5.6.1 with the differences listed in
///           {IAccessManager}'s dev notes; see the handler);
///         - role admins, guardians, grant delays, target roles and closed flags equal the model;
///         - `canCall` is consistent with `hasRole`, `getTargetFunctionRole` and `isTargetClosed`, and with the
///           model, and the manager is never an authorised caller outside `execute`;
///         - every scheduled operation's `getSchedule`/`getNonce` matches the model, so a spent or cancelled
///           schedule reads 0, and only authorised executions reach the target. That a schedule is spent at most
///           once is asserted in the handler: replaying a spent operation must revert `AccessManagerNotScheduled`.
/// forge-config: ci.invariant.runs = 64
contract AccessManagerDiamondInvariant is AccessManagedTestBase {
    AccessManagerHandler internal handler;
    InvCallSink internal sink;

    address internal constant ADMIN = address(0xAD);

    function setUp() public {
        vm.warp(1_000_000);
        authority = _deployAuthority(ADMIN);
        mgr = AccessManager(authority);
        diamond = _deployManaged(authority);
        sink = new InvCallSink();

        handler = new AccessManagerHandler(mgr, diamond, sink, ADMIN);
        handler.configure();

        bytes4[] memory selectors = new bytes4[](19);
        selectors[0] = AccessManagerHandler.warp.selector;
        selectors[1] = AccessManagerHandler.grantRole.selector;
        selectors[2] = AccessManagerHandler.revokeRole.selector;
        selectors[3] = AccessManagerHandler.renounceRole.selector;
        selectors[4] = AccessManagerHandler.setRoleAdmin.selector;
        selectors[5] = AccessManagerHandler.setRoleGuardian.selector;
        selectors[6] = AccessManagerHandler.setGrantDelay.selector;
        selectors[7] = AccessManagerHandler.setTargetFunctionRole.selector;
        selectors[8] = AccessManagerHandler.setTargetClosed.selector;
        selectors[9] = AccessManagerHandler.schedule.selector;
        selectors[10] = AccessManagerHandler.execute.selector;
        selectors[11] = AccessManagerHandler.directCall.selector;
        selectors[12] = AccessManagerHandler.cancel.selector;
        // Weight time, grants and the operation lifecycle, which carry the delay semantics.
        selectors[13] = AccessManagerHandler.warp.selector;
        selectors[14] = AccessManagerHandler.grantRole.selector;
        selectors[15] = AccessManagerHandler.schedule.selector;
        selectors[16] = AccessManagerHandler.execute.selector;
        selectors[17] = AccessManagerHandler.directCall.selector;
        selectors[18] = AccessManagerHandler.warp.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @notice `hasRole`, `getAccess` and the member set equal the model for every role and actor; the initial
    ///         admin keeps ADMIN_ROLE with no delay.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_RoleAccessMatchesModel() public view {
        uint64[4] memory roles = handler.roles();
        address[5] memory actors = handler.actors();
        for (uint256 i; i < roles.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                _checkAccess(roles[i], actors[j]);
            }
            address[] memory members = mgr.getRoleMembers(roles[i]);
            assertEq(members.length, handler.ghostMemberCount(roles[i]), "member count");
            assertEq(mgr.getRoleMemberCount(roles[i]), members.length, "getRoleMemberCount");
            for (uint256 k; k < members.length; ++k) {
                assertTrue(handler.isGranted(roles[i], members[k]), "member not granted in model");
            }
        }
        (bool adminIsMember, uint32 adminDelay) = mgr.hasRole(0, ADMIN);
        assertTrue(adminIsMember && adminDelay == 0, "initial admin lost ADMIN_ROLE");
    }

    function _checkAccess(uint64 role, address account) internal view {
        (bool isMember, uint32 delay) = mgr.hasRole(role, account);
        (bool mIsMember, uint32 mDelay) = handler.modelHasRole(role, account);
        assertEq(isMember, mIsMember, "hasRole membership");
        assertEq(delay, mDelay, "hasRole delay");

        (uint48 since, uint32 current, uint32 pending, uint48 effect) = mgr.getAccess(role, account);
        (uint48 mSince, uint32 mCurrent, uint32 mPending, uint48 mEffect) = handler.modelGetAccess(role, account);
        assertEq(since, mSince, "getAccess since");
        assertEq(current, mCurrent, "getAccess current delay");
        assertEq(pending, mPending, "getAccess pending delay");
        assertEq(effect, mEffect, "getAccess effect");
    }

    /// @notice Role admins, guardians, grant delays, target roles and closed flags equal the model.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ConfigMatchesModel() public view {
        uint64[4] memory roles = handler.roles();
        for (uint256 i; i < roles.length; ++i) {
            assertEq(mgr.getRoleAdmin(roles[i]), handler.ghostRoleAdmin(roles[i]), "role admin");
            assertEq(mgr.getRoleGuardian(roles[i]), handler.ghostRoleGuardian(roles[i]), "role guardian");
            assertEq(mgr.getRoleGrantDelay(roles[i]), handler.modelGrantDelay(roles[i]), "grant delay");
        }
        assertEq(
            mgr.getTargetFunctionRole(address(sink), InvCallSink.ping.selector),
            handler.ghostTargetRole(address(sink)),
            "sink role"
        );
        assertEq(
            mgr.getTargetFunctionRole(diamond, AccessManagedTestFacet.restrictedFn.selector),
            handler.ghostTargetRole(diamond),
            "managed role"
        );
        assertEq(mgr.isTargetClosed(address(sink)), handler.ghostClosed(address(sink)), "sink closed");
        assertEq(mgr.isTargetClosed(diamond), handler.ghostClosed(diamond), "managed closed");
    }

    /// @notice `canCall` follows from `isTargetClosed`, `getTargetFunctionRole` and `hasRole`, matches the model,
    ///         and never authorises the manager itself outside `execute`.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_CanCallConsistent() public view {
        address[5] memory actors = handler.actors();
        address[2] memory targets = [address(sink), diamond];
        bytes4[2] memory selectors = [InvCallSink.ping.selector, AccessManagedTestFacet.restrictedFn.selector];
        for (uint256 t; t < targets.length; ++t) {
            for (uint256 j; j < actors.length; ++j) {
                (bool immediate, uint32 delay) = mgr.canCall(actors[j], targets[t], selectors[t]);

                bool expImmediate;
                uint32 expDelay;
                if (!mgr.isTargetClosed(targets[t])) {
                    uint64 role = mgr.getTargetFunctionRole(targets[t], selectors[t]);
                    (bool isMember, uint32 d) = mgr.hasRole(role, actors[j]);
                    if (isMember) (expImmediate, expDelay) = d == 0 ? (true, uint32(0)) : (false, d);
                }
                assertEq(immediate, expImmediate, "canCall immediate vs hasRole");
                assertEq(delay, expDelay, "canCall delay vs hasRole");

                (bool mImmediate, uint32 mDelay) = handler.modelCanCall(actors[j], targets[t]);
                assertEq(immediate, mImmediate, "canCall immediate vs model");
                assertEq(delay, mDelay, "canCall delay vs model");
            }
            (bool selfImmediate, uint32 selfDelay) = mgr.canCall(authority, targets[t], selectors[t]);
            assertTrue(!selfImmediate && selfDelay == 0, "manager authorised outside execute");
        }
    }

    /// @notice Every tracked operation's schedule and nonce match the model (a spent or cancelled schedule reads
    ///         0), and the plain target was reached exactly by the authorised executions. Single use is enforced in
    ///         the handler, which expects `AccessManagerNotScheduled` on any replay of a spent operation.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ScheduledOpsMatchModel() public view {
        uint256 n = handler.opCount();
        for (uint256 i; i < n; ++i) {
            bytes32 opId = handler.opIds(i);
            assertEq(mgr.getSchedule(opId), handler.modelGetSchedule(opId), "getSchedule");
            assertEq(mgr.getNonce(opId), handler.ghostNonce(opId), "getNonce");
        }
        assertEq(sink.hits(), handler.ghostSinkHits(), "sink reached outside an authorised execute");
    }
}
