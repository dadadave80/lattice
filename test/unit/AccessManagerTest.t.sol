// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {AccessManagerTestBase} from "@lattice-test/base/AccessManagerTestBase.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {AccessManager} from "@lattice/access/AccessManager.sol";
import {AccessManagerInit} from "@lattice/access/AccessManagerInit.sol";
import {IAccessManager} from "@lattice/interfaces/access/IAccessManager.sol";
import {NotInitializing} from "@lattice/utils/libraries/InitializableLib.sol";
import {Vm} from "forge-std/Vm.sol";

contract CallSink {
    event Hit(uint256 v);

    error CustomTargetError(string what);

    function ping(uint256 v) external {
        emit Hit(v);
    }

    function alwaysReverts() external pure {
        revert CustomTargetError("nope");
    }

    function alwaysRevertsEmpty() external pure {
        // solidity 0.8 doesn't allow empty revert via `revert;`, use assembly to produce zero returndata
        assembly {
            revert(0, 0)
        }
    }
}

/// @notice T-4: Reentrant target used to confirm CEI ordering in execute().
///         Attempts to call execute() again with the same operationId from within the
///         first execute() call. The second attempt must fail because the schedule was
///         already cleared before the external call.
contract ReentrantTarget {
    address public manager;
    bytes public reentrantData;
    address public caller;
    bool public reentered;

    error ReentrantCallFailed();

    function configure(address _manager, bytes calldata _data, address _caller) external {
        manager = _manager;
        reentrantData = _data;
        caller = _caller;
    }

    /// @notice Called by AccessManager.execute(). Tries to re-enter execute() with the same data.
    function reentrantFn() external {
        // The schedule should already be cleared; the re-execution must revert.
        try IAccessManager(manager).execute(address(this), reentrantData) {
            // If we get here, CEI was violated — mark as erroneously reentered
            reentered = true;
        } catch {
            // Expected: revert because schedule is cleared
        }
    }
}

/// @notice #219 probe: a managed target whose `setAuthority` is reached through the manager's self-`execute` of
///         `updateAuthority`. It records what the manager reports for itself as caller while that call is in flight.
contract AuthorityProbeTarget {
    address public authority;
    bool public selfImmediateInFlight; // canCall(manager, manager, updateAuthority) during the execute
    bool public selfImmediateOther; // canCall(manager, manager, setTargetClosed) during the execute

    constructor(address authority_) {
        authority = authority_;
    }

    function setAuthority(address newAuthority) external {
        IAccessManager manager = IAccessManager(msg.sender);
        (selfImmediateInFlight,) = manager.canCall(msg.sender, msg.sender, IAccessManager.updateAuthority.selector);
        (selfImmediateOther,) = manager.canCall(msg.sender, msg.sender, IAccessManager.setTargetClosed.selector);
        authority = newAuthority;
    }
}

/// @notice #219: a contract that is not consuming a scheduled operation (it reports `0`).
contract NonConsumingTarget {
    function isConsumingScheduledOp() external pure returns (bytes4) {
        return bytes4(0);
    }

    function consume(IAccessManager manager, address caller, bytes calldata data) external {
        manager.consumeScheduledOp(caller, data);
    }
}

/// @title AccessManagerTest
/// @notice Exercises the AccessManager authority facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployAccessManager} script (see {AccessManagerTestBase}) — every authority call (roles, targets,
///         schedule/execute/cancel) routes through the diamond's `delegatecall` dispatch, not a flattened
///         inheritance mock. The AccessManager self-gates its whole surface on `ADMIN_ROLE`.
contract AccessManagerTest is AccessManagerTestBase {
    uint64 constant ADMIN_ROLE = 0;
    uint64 constant PUBLIC_ROLE = type(uint64).max;
    uint64 constant MINTER_ROLE = 1;

    address internal admin = address(0xA1);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        vm.warp(1_000_000);
        diamond = _deployAccessManager(admin);
        mgr = AccessManager(diamond);
    }

    function test_AdminInitiallyHasAdminRole() public view {
        (bool isMember, uint32 delay) = mgr.hasRole(ADMIN_ROLE, admin);
        assertTrue(isMember);
        assertEq(delay, 0);
        assertEq(mgr.getRoleMemberCount(ADMIN_ROLE), 1);
        assertEq(mgr.getRoleMembers(ADMIN_ROLE)[0], admin);
    }

    function test_PublicRoleHasEveryone() public view {
        (bool isMember, uint32 delay) = mgr.hasRole(PUBLIC_ROLE, address(0xDEAD));
        assertTrue(isMember);
        assertEq(delay, 0);
    }

    function test_InvalidInitialAdminReverts() public {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(address(0));
        Lattice d = new Lattice();
        vm.expectRevert(IAccessManager.AccessManagerInvalidInitialAdmin.selector);
        d.initialize(cuts, init, initCalldata);
    }

    function test_GrantRoleAddsMemberAfterDelay() public {
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 0);
        (bool isMember, uint32 execDelay) = mgr.hasRole(MINTER_ROLE, alice);
        assertTrue(isMember);
        assertEq(execDelay, 0);
    }

    function test_GrantRoleRespectsGrantDelay() public {
        vm.prank(admin);
        mgr.setGrantDelay(MINTER_ROLE, 1 days);

        // Wait for grant delay change to take effect (MIN_SETBACK = 5 days for increases;
        // we warp 1 week to comfortably clear the setback).
        vm.warp(block.timestamp + 1 weeks);

        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 0);

        (bool isMember,) = mgr.hasRole(MINTER_ROLE, alice);
        assertFalse(isMember);

        vm.warp(block.timestamp + 1 days);
        (isMember,) = mgr.hasRole(MINTER_ROLE, alice);
        assertTrue(isMember);
    }

    /// @dev Pins the documented difference from OZ: before the grant delay has passed, `hasRole` reports
    ///      `(false, 0)` where OZ reports `(false, delay)`; `getAccess` still shows the stored delay.
    function test_HasRoleReportsZeroDelayWhileGrantPending() public {
        vm.prank(admin);
        mgr.setGrantDelay(MINTER_ROLE, 1 days);
        vm.warp(block.timestamp + 1 weeks);

        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 3 days);

        (bool isMember, uint32 execDelay) = mgr.hasRole(MINTER_ROLE, alice);
        assertFalse(isMember);
        assertEq(execDelay, 0);
        (, uint32 currentDelay,,) = mgr.getAccess(MINTER_ROLE, alice);
        assertEq(currentDelay, 3 days);

        vm.warp(block.timestamp + 1 days);
        (isMember, execDelay) = mgr.hasRole(MINTER_ROLE, alice);
        assertTrue(isMember);
        assertEq(execDelay, 3 days);
    }

    function test_RevokeRoleClearsMembership() public {
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 0);
        vm.prank(admin);
        mgr.revokeRole(MINTER_ROLE, alice);
        (bool isMember,) = mgr.hasRole(MINTER_ROLE, alice);
        assertFalse(isMember);
    }

    function test_RenounceRoleClearsMembershipForSelf() public {
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 0);
        vm.prank(alice);
        mgr.renounceRole(MINTER_ROLE, alice);
        (bool isMember,) = mgr.hasRole(MINTER_ROLE, alice);
        assertFalse(isMember);
    }

    function test_RenounceWithBadConfirmationReverts() public {
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 0);
        vm.prank(alice);
        vm.expectRevert(IAccessManager.AccessManagerBadConfirmation.selector);
        mgr.renounceRole(MINTER_ROLE, bob);
    }

    function test_GrantRoleByNonAdminReverts() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedAccount.selector, alice, ADMIN_ROLE)
        );
        mgr.grantRole(MINTER_ROLE, alice, 0);
    }

    function test_GrantAdminRoleReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerLockedRole.selector, ADMIN_ROLE));
        mgr.grantRole(ADMIN_ROLE, alice, 0);
    }

    function test_GrantPublicRoleReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerLockedRole.selector, PUBLIC_ROLE));
        mgr.grantRole(PUBLIC_ROLE, alice, 0);
    }

    function test_SetRoleAdminUpdatesRole() public {
        uint64 SUPER_ROLE = 2;
        vm.prank(admin);
        mgr.setRoleAdmin(MINTER_ROLE, SUPER_ROLE);
        assertEq(mgr.getRoleAdmin(MINTER_ROLE), SUPER_ROLE);
    }

    function test_SetRoleGuardianUpdatesRole() public {
        uint64 GUARDIAN_ROLE = 7;
        vm.prank(admin);
        mgr.setRoleGuardian(MINTER_ROLE, GUARDIAN_ROLE);
        assertEq(mgr.getRoleGuardian(MINTER_ROLE), GUARDIAN_ROLE);
    }

    function test_SetGrantDelayIncreaseRequiresWait() public {
        vm.prank(admin);
        mgr.setGrantDelay(MINTER_ROLE, 3 days);
        assertEq(mgr.getRoleGrantDelay(MINTER_ROLE), 0);
        vm.warp(block.timestamp + 1 weeks);
        assertEq(mgr.getRoleGrantDelay(MINTER_ROLE), 3 days);
    }

    function test_SetGrantDelayDecreaseUsesMinSetback() public {
        vm.prank(admin);
        mgr.setGrantDelay(MINTER_ROLE, 3 days);
        vm.warp(block.timestamp + 5 days);
        assertEq(mgr.getRoleGrantDelay(MINTER_ROLE), 3 days);

        // Decrease from 3 days to 1 day: diff=2 days < MIN_SETBACK=5 days, so wait=5 days.
        vm.prank(admin);
        mgr.setGrantDelay(MINTER_ROLE, 1 days);
        // Not yet effective
        assertEq(mgr.getRoleGrantDelay(MINTER_ROLE), 3 days);
        // After MIN_SETBACK
        vm.warp(block.timestamp + 5 days);
        assertEq(mgr.getRoleGrantDelay(MINTER_ROLE), 1 days);
    }

    function test_LabelRoleEmitsEvent() public {
        vm.recordLogs();
        vm.prank(admin);
        mgr.labelRole(MINTER_ROLE, "MINTER");

        bytes32 sig = keccak256("RoleLabel(uint64,string)");
        bool found = false;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == sig) found = true;
        }
        assertTrue(found);
    }

    function test_SetTargetFunctionRoleStoresRole() public {
        address target = address(0xBEEF);
        bytes4 sel = bytes4(keccak256("mint(uint256)"));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;

        vm.prank(admin);
        mgr.setTargetFunctionRole(target, selectors, MINTER_ROLE);
        assertEq(mgr.getTargetFunctionRole(target, sel), MINTER_ROLE);
    }

    function test_CanCallWithMatchingRoleReturnsImmediate() public {
        address target = address(0xBEEF);
        bytes4 sel = bytes4(keccak256("mint(uint256)"));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;

        vm.prank(admin);
        mgr.setTargetFunctionRole(target, selectors, MINTER_ROLE);

        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 0);

        (bool immediate, uint32 delay) = mgr.canCall(alice, target, sel);
        assertTrue(immediate);
        assertEq(delay, 0);
    }

    function test_CanCallWithExecutionDelayReturnsDelayed() public {
        address target = address(0xBEEF);
        bytes4 sel = bytes4(keccak256("mint(uint256)"));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;

        vm.prank(admin);
        mgr.setTargetFunctionRole(target, selectors, MINTER_ROLE);

        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, uint32(1 days));

        (bool immediate, uint32 delay) = mgr.canCall(alice, target, sel);
        assertFalse(immediate);
        assertEq(delay, 1 days);
    }

    function test_CanCallClosedTargetReturnsFalse() public {
        address target = address(0xBEEF);
        bytes4 sel = bytes4(keccak256("mint(uint256)"));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;

        vm.prank(admin);
        mgr.setTargetFunctionRole(target, selectors, PUBLIC_ROLE);

        vm.prank(admin);
        mgr.setTargetClosed(target, true);

        (bool immediate, uint32 delay) = mgr.canCall(alice, target, sel);
        assertFalse(immediate);
        assertEq(delay, 0);
    }

    function test_CanCallPublicRoleAllowsAnyone() public {
        address target = address(0xBEEF);
        bytes4 sel = bytes4(keccak256("openFn()"));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;

        vm.prank(admin);
        mgr.setTargetFunctionRole(target, selectors, PUBLIC_ROLE);

        (bool immediate,) = mgr.canCall(address(0xDEAD), target, sel);
        assertTrue(immediate);
    }

    function test_ExecuteImmediateWorks() public {
        CallSink sink = new CallSink();
        bytes4 sel = sink.ping.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(sink), selectors, MINTER_ROLE);
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 0);

        bytes memory data = abi.encodeCall(CallSink.ping, (42));
        vm.prank(alice);
        mgr.execute(address(sink), data);
    }

    function test_ScheduleThenExecuteAfterDelay() public {
        CallSink sink = new CallSink();
        bytes4 sel = sink.ping.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(sink), selectors, MINTER_ROLE);
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, uint32(1 days));

        bytes memory data = abi.encodeCall(CallSink.ping, (42));

        vm.prank(alice);
        (bytes32 opId, uint32 nonce) = mgr.schedule(address(sink), data, uint48(block.timestamp + 1 days));
        assertGt(uint256(opId), 0);
        assertEq(nonce, 1);

        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotReady.selector, opId));
        vm.prank(alice);
        mgr.execute(address(sink), data);

        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        mgr.execute(address(sink), data);

        assertEq(mgr.getSchedule(opId), 0);
    }

    function test_CancelByOriginalCallerWorks() public {
        CallSink sink = new CallSink();
        bytes4 sel = sink.ping.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(sink), selectors, MINTER_ROLE);
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, uint32(1 days));

        bytes memory data = abi.encodeCall(CallSink.ping, (42));
        vm.prank(alice);
        mgr.schedule(address(sink), data, uint48(block.timestamp + 1 days));

        vm.prank(alice);
        mgr.cancel(alice, address(sink), data);

        bytes32 opId = mgr.hashOperation(alice, address(sink), data);
        assertEq(mgr.getSchedule(opId), 0);
    }

    function test_CancelByUnauthorizedReverts() public {
        CallSink sink = new CallSink();
        bytes4 sel = sink.ping.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(sink), selectors, MINTER_ROLE);
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, uint32(1 days));

        bytes memory data = abi.encodeCall(CallSink.ping, (42));
        vm.prank(alice);
        mgr.schedule(address(sink), data, uint48(block.timestamp + 1 days));

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedCancel.selector, bob, address(sink))
        );
        mgr.cancel(alice, address(sink), data);
    }

    function test_ScheduleByUnauthorizedReverts() public {
        CallSink sink = new CallSink();
        bytes4 sel = sink.ping.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(sink), selectors, MINTER_ROLE);

        bytes memory data = abi.encodeCall(CallSink.ping, (42));
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedAccount.selector, alice, MINTER_ROLE)
        );
        mgr.schedule(address(sink), data, uint48(block.timestamp + 1 days));
    }

    function test_ScheduleImmediateCallerReverts() public {
        CallSink sink = new CallSink();
        bytes4 sel = sink.ping.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;

        // Grant alice immediate access (no execution delay)
        vm.prank(admin);
        mgr.setTargetFunctionRole(address(sink), selectors, MINTER_ROLE);
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 0);

        bytes memory data = abi.encodeCall(CallSink.ping, (42));
        bytes32 opId = mgr.hashOperation(alice, address(sink), data);

        // Alice has immediate access — schedule should revert
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, opId));
        mgr.schedule(address(sink), data, uint48(block.timestamp + 1 days));
    }

    function test_AdminCanCancelAnyOperation() public {
        CallSink sink = new CallSink();
        bytes4 sel = sink.ping.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(sink), selectors, MINTER_ROLE);
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, uint32(1 days));

        bytes memory data = abi.encodeCall(CallSink.ping, (42));
        vm.prank(alice);
        mgr.schedule(address(sink), data, uint48(block.timestamp + 1 days));

        // Admin (not the original caller) can cancel alice's operation
        vm.prank(admin);
        mgr.cancel(alice, address(sink), data);

        bytes32 opId = mgr.hashOperation(alice, address(sink), data);
        assertEq(mgr.getSchedule(opId), 0);
    }

    function test_GetScheduleReturns0ForExpired() public {
        CallSink sink = new CallSink();
        bytes4 sel = sink.ping.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(sink), selectors, MINTER_ROLE);
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, uint32(1 days));

        bytes memory data = abi.encodeCall(CallSink.ping, (42));
        vm.prank(alice);
        (bytes32 opId,) = mgr.schedule(address(sink), data, uint48(block.timestamp + 1 days));

        // Before expiration, getSchedule returns nonzero
        vm.warp(block.timestamp + 1 days);
        assertGt(mgr.getSchedule(opId), 0);

        // After expiration (readyAt + 1 week), getSchedule returns 0
        vm.warp(block.timestamp + 1 weeks + 1);
        assertEq(mgr.getSchedule(opId), 0);
    }

    function test_RescheduleExpiredOperation() public {
        CallSink sink = new CallSink();
        bytes4 sel = sink.ping.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(sink), selectors, MINTER_ROLE);
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, uint32(1 days));

        bytes memory data = abi.encodeCall(CallSink.ping, (42));
        vm.prank(alice);
        mgr.schedule(address(sink), data, uint48(block.timestamp + 1 days));

        // Warp past expiration
        vm.warp(block.timestamp + 1 days + 1 weeks + 1);

        // Reschedule should succeed (expired = allowed)
        vm.prank(alice);
        (bytes32 opId, uint32 nonce) = mgr.schedule(address(sink), data, uint48(block.timestamp + 1 days));
        assertGt(nonce, 1);
        assertGt(uint256(opId), 0);
    }

    function test_ExecuteBubblesUpTargetRevertReason() public {
        CallSink sink = new CallSink();
        bytes4 sel = sink.alwaysReverts.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(sink), selectors, PUBLIC_ROLE);

        bytes memory data = abi.encodeCall(CallSink.alwaysReverts, ());
        vm.expectRevert(abi.encodeWithSelector(CallSink.CustomTargetError.selector, "nope"));
        mgr.execute(address(sink), data);
    }

    function test_ExecuteEmptyRevertUsesTypedTargetCallFailedError() public {
        CallSink sink = new CallSink();
        bytes4 sel = sink.alwaysRevertsEmpty.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(sink), selectors, PUBLIC_ROLE);

        bytes memory data = abi.encodeCall(CallSink.alwaysRevertsEmpty, ());
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerTargetCallFailed.selector, address(sink)));
        mgr.execute(address(sink), data);
    }

    /// @notice T-4: CEI ordering — a reentrant target that tries to re-call execute() with
    ///         the same operationId cannot double-execute because the schedule is cleared before
    ///         the external call.
    function test_ReentrantExecuteCannotDoubleExecute() public {
        ReentrantTarget rt = new ReentrantTarget();
        bytes4 sel = rt.reentrantFn.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(rt), selectors, MINTER_ROLE);
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, uint32(1 days));

        bytes memory data = abi.encodeCall(ReentrantTarget.reentrantFn, ());

        // Configure the reentrant target with the manager, data, and caller
        rt.configure(address(mgr), data, alice);

        // Schedule
        vm.prank(alice);
        (bytes32 opId,) = mgr.schedule(address(rt), data, uint48(block.timestamp + 1 days));

        vm.warp(block.timestamp + 1 days);

        // Execute: the reentrant attempt inside reentrantFn() must fail silently
        vm.prank(alice);
        mgr.execute(address(rt), data);

        // The schedule must be cleared (consumed, not double-executed)
        assertEq(mgr.getSchedule(opId), 0);

        // The reentrant call must have been rejected (reentered == false)
        assertFalse(rt.reentered(), "CEI violated: reentrant execute succeeded");
    }

    /// @notice OZ `Time.Delay.withUpdate` parity (#219, replaces the M-5 no-op): re-setting the current grant delay
    ///         still records a change taking effect MIN_SETBACK away, and the effective value never moves.
    function test_SetGrantDelaySameValueAppliesMinSetback() public {
        vm.prank(admin);
        mgr.setGrantDelay(MINTER_ROLE, 1 days);
        vm.warp(block.timestamp + 1 weeks); // let delay take effect
        assertEq(mgr.getRoleGrantDelay(MINTER_ROLE), 1 days);

        uint48 effectAt = uint48(block.timestamp + 5 days);
        vm.expectEmit(true, false, false, true, diamond);
        emit IAccessManager.RoleGrantDelayChanged(MINTER_ROLE, 1 days, effectAt);
        vm.prank(admin);
        mgr.setGrantDelay(MINTER_ROLE, 1 days);

        assertEq(mgr.getRoleGrantDelay(MINTER_ROLE), 1 days);
        vm.warp(effectAt);
        assertEq(mgr.getRoleGrantDelay(MINTER_ROLE), 1 days);
    }

    /// @notice #219: re-setting the delay in force replaces a pending decrease, as in OZ, so the decrease never lands.
    function test_SetGrantDelaySameValueCancelsPendingDecrease() public {
        vm.prank(admin);
        mgr.setGrantDelay(MINTER_ROLE, 10 days);
        vm.warp(block.timestamp + 5 days);
        assertEq(mgr.getRoleGrantDelay(MINTER_ROLE), 10 days);

        // 10 days -> 1 day waits out the 9-day difference.
        vm.prank(admin);
        mgr.setGrantDelay(MINTER_ROLE, 1 days);
        vm.prank(admin);
        mgr.setGrantDelay(MINTER_ROLE, 10 days);

        vm.warp(block.timestamp + 9 days + 1);
        assertEq(mgr.getRoleGrantDelay(MINTER_ROLE), 10 days, "pending decrease was cancelled");
    }

    /// @notice TimelockLib.reschedule M-3 regression: reschedule with 0 must revert.
    function test_TimelockRescheduleZeroIsRejected() public {
        // Create a scheduled operation
        CallSink sink = new CallSink();
        bytes4 sel = sink.ping.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(sink), selectors, MINTER_ROLE);
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, uint32(1 days));

        bytes memory data = abi.encodeCall(CallSink.ping, (1));
        vm.prank(alice);
        mgr.schedule(address(sink), data, uint48(block.timestamp + 1 days));

        // AccessManager does not expose reschedule; TimelockLib tested directly in TimelockLibTest
        // This test documents the gap — the unit coverage lives in TimelockLibTest.t.sol.
        // See test_RescheduleZeroReadyAtReverts in TimelockLibTest.
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    #219: TARGET ADMIN DELAY (SETTER)
    //////////////////////////////////////////////////////////////////////////*//

    uint32 constant MIN_SETBACK = 5 days;
    address constant TARGET = address(0xBEEF);

    /// @notice Sets `target`'s admin delay to `delay` and waits until it is in force.
    function _setAdminDelayInForce(address target, uint32 delay) internal {
        vm.prank(admin);
        mgr.setTargetAdminDelay(target, delay);
        vm.warp(block.timestamp + (delay > MIN_SETBACK ? delay : MIN_SETBACK));
        assertEq(mgr.getTargetAdminDelay(target), delay);
    }

    function test_SetTargetAdminDelay_IncreaseTakesEffectAfterMinSetback() public {
        uint48 effectAt = uint48(block.timestamp + MIN_SETBACK);
        vm.expectEmit(true, false, false, true, diamond);
        emit IAccessManager.TargetAdminDelayUpdated(TARGET, 3 days, effectAt);
        vm.prank(admin);
        mgr.setTargetAdminDelay(TARGET, 3 days);

        assertEq(mgr.getTargetAdminDelay(TARGET), 0);
        vm.warp(effectAt - 1);
        assertEq(mgr.getTargetAdminDelay(TARGET), 0);
        vm.warp(effectAt);
        assertEq(mgr.getTargetAdminDelay(TARGET), 3 days);
    }

    function test_SetTargetAdminDelay_LargeDecreaseWaitsForTheDifference() public {
        _setAdminDelayInForce(TARGET, 10 days);

        // 10 days -> 1 day: the 9-day difference exceeds MIN_SETBACK, so it sets the wait.
        uint48 effectAt = uint48(block.timestamp + 9 days);
        vm.expectEmit(true, false, false, true, diamond);
        emit IAccessManager.TargetAdminDelayUpdated(TARGET, 1 days, effectAt);
        vm.prank(admin);
        mgr.setTargetAdminDelay(TARGET, 1 days);

        vm.warp(effectAt - 1);
        assertEq(mgr.getTargetAdminDelay(TARGET), 10 days);
        vm.warp(effectAt);
        assertEq(mgr.getTargetAdminDelay(TARGET), 1 days);
    }

    function test_SetTargetAdminDelay_SmallDecreaseWaitsMinSetback() public {
        _setAdminDelayInForce(TARGET, 3 days);

        // 3 days -> 1 day: the 2-day difference is below MIN_SETBACK, so MIN_SETBACK applies.
        uint48 effectAt = uint48(block.timestamp + MIN_SETBACK);
        vm.expectEmit(true, false, false, true, diamond);
        emit IAccessManager.TargetAdminDelayUpdated(TARGET, 1 days, effectAt);
        vm.prank(admin);
        mgr.setTargetAdminDelay(TARGET, 1 days);

        vm.warp(effectAt - 1);
        assertEq(mgr.getTargetAdminDelay(TARGET), 3 days);
        vm.warp(effectAt);
        assertEq(mgr.getTargetAdminDelay(TARGET), 1 days);
    }

    /// @notice OZ `Time.Delay.withUpdate` parity: re-setting the current value still reports an effect time
    ///         MIN_SETBACK away, and the effective value never changes.
    function test_SetTargetAdminDelay_EqualValueAppliesMinSetback() public {
        _setAdminDelayInForce(TARGET, 2 days);

        uint48 effectAt = uint48(block.timestamp + MIN_SETBACK);
        vm.expectEmit(true, false, false, true, diamond);
        emit IAccessManager.TargetAdminDelayUpdated(TARGET, 2 days, effectAt);
        vm.prank(admin);
        mgr.setTargetAdminDelay(TARGET, 2 days);

        assertEq(mgr.getTargetAdminDelay(TARGET), 2 days);
        vm.warp(effectAt);
        assertEq(mgr.getTargetAdminDelay(TARGET), 2 days);
    }

    /// @notice A pending change that has not taken effect is replaced, measured from the delay still in force.
    function test_SetTargetAdminDelay_ReplacesPendingChange() public {
        vm.prank(admin);
        mgr.setTargetAdminDelay(TARGET, 3 days);
        vm.warp(block.timestamp + 1 days);

        uint48 effectAt = uint48(block.timestamp + MIN_SETBACK);
        vm.prank(admin);
        mgr.setTargetAdminDelay(TARGET, 4 days);

        vm.warp(effectAt - 1);
        assertEq(mgr.getTargetAdminDelay(TARGET), 0);
        vm.warp(effectAt);
        assertEq(mgr.getTargetAdminDelay(TARGET), 4 days);
    }

    function test_SetTargetAdminDelay_NonAdminReverts() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedAccount.selector, alice, ADMIN_ROLE)
        );
        mgr.setTargetAdminDelay(TARGET, 1 days);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                  #219: TARGET ADMIN DELAY (ENFORCEMENT)
    //////////////////////////////////////////////////////////////////////////*//

    function _selectors(bytes4 sel) internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = sel;
    }

    function test_AdminDelay_ImmediateSetTargetFunctionRoleReverts() public {
        _setAdminDelayInForce(TARGET, 2 days);

        bytes memory data =
            abi.encodeCall(IAccessManager.setTargetFunctionRole, (TARGET, _selectors(0x12345678), PUBLIC_ROLE));
        bytes32 opId = mgr.hashOperation(admin, diamond, data);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, opId));
        mgr.setTargetFunctionRole(TARGET, _selectors(0x12345678), PUBLIC_ROLE);
        assertEq(mgr.getTargetFunctionRole(TARGET, 0x12345678), ADMIN_ROLE);
    }

    function test_AdminDelay_ImmediateSetTargetClosedReverts() public {
        _setAdminDelayInForce(TARGET, 2 days);

        bytes32 opId = mgr.hashOperation(admin, diamond, abi.encodeCall(IAccessManager.setTargetClosed, (TARGET, true)));
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, opId));
        mgr.setTargetClosed(TARGET, true);
        assertFalse(mgr.isTargetClosed(TARGET));
    }

    function test_AdminDelay_ImmediateUpdateAuthorityReverts() public {
        AuthorityProbeTarget probe = new AuthorityProbeTarget(diamond);
        _setAdminDelayInForce(address(probe), 2 days);

        bytes memory data = abi.encodeCall(IAccessManager.updateAuthority, (address(probe), address(0x1234)));
        bytes32 opId = mgr.hashOperation(admin, diamond, data);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, opId));
        mgr.updateAuthority(address(probe), address(0x1234));
        assertEq(probe.authority(), diamond);
    }

    /// @notice The scheduled call fails before the delay and succeeds through `execute(address(this), ...)` after it.
    function test_AdminDelay_ScheduledSetTargetClosedRunsThroughExecute() public {
        _setAdminDelayInForce(TARGET, 2 days);
        bytes memory data = abi.encodeCall(IAccessManager.setTargetClosed, (TARGET, true));

        vm.prank(admin);
        (bytes32 opId,) = mgr.schedule(diamond, data, 0);
        assertEq(opId, mgr.hashOperation(admin, diamond, data));
        assertEq(mgr.getSchedule(opId), block.timestamp + 2 days);

        vm.warp(block.timestamp + 2 days - 1);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotReady.selector, opId));
        mgr.execute(diamond, data);

        vm.warp(block.timestamp + 1);
        vm.prank(admin);
        mgr.execute(diamond, data);
        assertTrue(mgr.isTargetClosed(TARGET));
        assertEq(mgr.getSchedule(opId), 0, "schedule consumed");

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, opId));
        mgr.execute(diamond, data);
    }

    /// @notice The scheduled call can also be made directly once ready: the admin check consumes the schedule.
    function test_AdminDelay_ScheduledSetTargetFunctionRoleRunsDirectly() public {
        _setAdminDelayInForce(TARGET, 2 days);
        bytes memory data =
            abi.encodeCall(IAccessManager.setTargetFunctionRole, (TARGET, _selectors(0x12345678), MINTER_ROLE));

        vm.prank(admin);
        (bytes32 opId, uint32 nonce) = mgr.schedule(diamond, data, 0);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotReady.selector, opId));
        mgr.setTargetFunctionRole(TARGET, _selectors(0x12345678), MINTER_ROLE);

        vm.warp(block.timestamp + 2 days);
        vm.expectEmit(true, true, false, false, diamond);
        emit IAccessManager.OperationExecuted(opId, nonce);
        vm.prank(admin);
        mgr.setTargetFunctionRole(TARGET, _selectors(0x12345678), MINTER_ROLE);
        assertEq(mgr.getTargetFunctionRole(TARGET, 0x12345678), MINTER_ROLE);
        assertEq(mgr.getSchedule(opId), 0, "schedule consumed");

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, opId));
        mgr.setTargetFunctionRole(TARGET, _selectors(0x12345678), MINTER_ROLE);
    }

    /// @notice A target with admin delay 0 keeps immediate admin control, and there is nothing to schedule.
    function test_AdminDelay_ZeroDelayStaysImmediate() public {
        vm.prank(admin);
        mgr.setTargetClosed(TARGET, true);
        assertTrue(mgr.isTargetClosed(TARGET));

        bytes memory data = abi.encodeCall(IAccessManager.setTargetClosed, (TARGET, false));
        bytes32 opId = mgr.hashOperation(admin, diamond, data);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, opId));
        mgr.schedule(diamond, data, 0);

        // ... and the self-execute path runs it immediately.
        vm.prank(admin);
        mgr.execute(diamond, data);
        assertFalse(mgr.isTargetClosed(TARGET));
    }

    /// @notice The delay binds only the target it was set on, and only the target-scoped admin functions.
    function test_AdminDelay_ScopedToTargetAndTargetFunctions() public {
        _setAdminDelayInForce(TARGET, 2 days);

        vm.startPrank(admin);
        mgr.setTargetClosed(address(0xCAFE), true);
        mgr.setTargetAdminDelay(TARGET, 3 days);
        mgr.setRoleGuardian(MINTER_ROLE, 7);
        mgr.grantRole(MINTER_ROLE, alice, 0);
        vm.stopPrank();
        assertTrue(mgr.isTargetClosed(address(0xCAFE)));
        assertEq(mgr.getRoleGuardian(MINTER_ROLE), 7);
    }

    /// @notice OZ parity: `execute` consumes an available schedule even when no delay is enforced any more.
    function test_AdminDelay_ExecuteConsumesScheduleAfterDelayDropsToZero() public {
        _setAdminDelayInForce(TARGET, 1 days);
        bytes memory data = abi.encodeCall(IAccessManager.setTargetClosed, (TARGET, true));
        vm.prank(admin);
        (bytes32 opId,) = mgr.schedule(diamond, data, 0);

        vm.prank(admin);
        mgr.setTargetAdminDelay(TARGET, 0);
        vm.warp(block.timestamp + MIN_SETBACK);
        assertEq(mgr.getTargetAdminDelay(TARGET), 0);
        assertGt(mgr.getSchedule(opId), 0);

        vm.prank(admin);
        mgr.execute(diamond, data);
        assertTrue(mgr.isTargetClosed(TARGET));
        assertEq(mgr.getSchedule(opId), 0, "schedule consumed");
    }

    /// @notice During a self-`execute`, the manager accepts itself as caller only for the selector it is executing.
    function test_SelfExecute_AcceptsManagerOnlyForExecutedSelector() public {
        AuthorityProbeTarget probe = new AuthorityProbeTarget(diamond);
        _setAdminDelayInForce(address(probe), 1 days);

        bytes memory data = abi.encodeCall(IAccessManager.updateAuthority, (address(probe), address(0x1234)));
        vm.prank(admin);
        mgr.schedule(diamond, data, 0);
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        mgr.execute(diamond, data);

        assertEq(probe.authority(), address(0x1234));
        assertTrue(probe.selfImmediateInFlight(), "manager accepted for the in-flight selector");
        assertFalse(probe.selfImmediateOther(), "manager accepted for another selector");

        (bool immediate,) = mgr.canCall(diamond, diamond, IAccessManager.updateAuthority.selector);
        assertFalse(immediate, "manager still accepted after execute");
    }

    /// @notice OZ `_canCallSelf`: closing the manager itself does not lock its admin-restricted functions.
    function test_ClosedManagerKeepsAdminFunctions() public {
        vm.prank(admin);
        mgr.setTargetClosed(diamond, true);
        assertTrue(mgr.isTargetClosed(diamond));

        vm.prank(admin);
        mgr.setTargetClosed(diamond, false);
        assertFalse(mgr.isTargetClosed(diamond));
    }

    /// @notice Outside `execute`, the manager cannot call its own admin functions.
    function test_SelfCallOutsideExecuteReverts() public {
        vm.prank(diamond);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedAccount.selector, diamond, ADMIN_ROLE)
        );
        mgr.setTargetClosed(TARGET, true);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      #219: ROLE ADMIN EXECUTION DELAY
    //////////////////////////////////////////////////////////////////////////*//

    uint64 constant SUPER_ROLE = 2;

    /// @notice Makes `alice` the admin of MINTER_ROLE through SUPER_ROLE, with `delay` as her execution delay.
    function _setUpRoleAdmin(uint32 delay) internal {
        vm.startPrank(admin);
        mgr.setRoleAdmin(MINTER_ROLE, SUPER_ROLE);
        mgr.grantRole(SUPER_ROLE, alice, delay);
        vm.stopPrank();
    }

    function test_RoleAdminDelay_ImmediateGrantRoleReverts() public {
        _setUpRoleAdmin(1 days);

        bytes memory data = abi.encodeCall(IAccessManager.grantRole, (MINTER_ROLE, bob, 0));
        bytes32 opId = mgr.hashOperation(alice, diamond, data);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, opId));
        mgr.grantRole(MINTER_ROLE, bob, 0);
        (bool isMember,) = mgr.hasRole(MINTER_ROLE, bob);
        assertFalse(isMember);
    }

    function test_RoleAdminDelay_ScheduledGrantRoleRunsThroughExecute() public {
        _setUpRoleAdmin(1 days);

        bytes memory data = abi.encodeCall(IAccessManager.grantRole, (MINTER_ROLE, bob, 0));
        vm.prank(alice);
        (bytes32 opId,) = mgr.schedule(diamond, data, 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotReady.selector, opId));
        mgr.execute(diamond, data);

        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        mgr.execute(diamond, data);
        (bool isMember,) = mgr.hasRole(MINTER_ROLE, bob);
        assertTrue(isMember);
        assertEq(mgr.getSchedule(opId), 0, "schedule consumed");
    }

    function test_RoleAdminDelay_ScheduledRevokeRoleRunsDirectly() public {
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, bob, 0);
        _setUpRoleAdmin(1 days);

        bytes memory data = abi.encodeCall(IAccessManager.revokeRole, (MINTER_ROLE, bob));
        bytes32 opId = mgr.hashOperation(alice, diamond, data);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, opId));
        mgr.revokeRole(MINTER_ROLE, bob);

        vm.prank(alice);
        mgr.schedule(diamond, data, 0);
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        mgr.revokeRole(MINTER_ROLE, bob);
        (bool isMember,) = mgr.hasRole(MINTER_ROLE, bob);
        assertFalse(isMember);
        assertEq(mgr.getSchedule(opId), 0, "schedule consumed");
    }

    function test_RoleAdminWithoutDelay_GrantsImmediately() public {
        _setUpRoleAdmin(0);

        vm.prank(alice);
        mgr.grantRole(MINTER_ROLE, bob, 0);
        (bool isMember,) = mgr.hasRole(MINTER_ROLE, bob);
        assertTrue(isMember);
    }

    /// @notice A delayed role admin's schedule covers only the roles it administers.
    function test_RoleAdminDelay_CannotScheduleForOtherRoles() public {
        _setUpRoleAdmin(1 days);

        bytes memory data = abi.encodeCall(IAccessManager.grantRole, (uint64(3), bob, 0));
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedAccount.selector, alice, ADMIN_ROLE)
        );
        mgr.schedule(diamond, data, 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        #219: consumeScheduledOp
    //////////////////////////////////////////////////////////////////////////*//

    function test_ConsumeScheduledOp_RevertsUnlessTargetIsConsuming() public {
        NonConsumingTarget t = new NonConsumingTarget();
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedConsume.selector, address(t)));
        t.consume(IAccessManager(diamond), alice, hex"12345678");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    #219: EXPIRATION (OZ `_isExpired` PARITY)
    //////////////////////////////////////////////////////////////////////////*//

    uint32 constant EXPIRATION = 1 weeks;

    /// @notice Schedules `setTargetClosed(TARGET, true)` against a 1-day admin delay; returns its id and readyAt.
    function _scheduleDelayedClose() internal returns (bytes memory data, bytes32 opId, uint48 readyAt) {
        _setAdminDelayInForce(TARGET, 1 days);
        data = abi.encodeCall(IAccessManager.setTargetClosed, (TARGET, true));
        vm.prank(admin);
        (opId,) = mgr.schedule(diamond, data, 0);
        readyAt = mgr.getSchedule(opId);
    }

    function test_Expiry_DirectAdminCallRevertsExpired() public {
        (, bytes32 opId, uint48 readyAt) = _scheduleDelayedClose();
        vm.warp(uint256(readyAt) + EXPIRATION + 1 days);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerExpired.selector, opId));
        mgr.setTargetClosed(TARGET, true);
        assertFalse(mgr.isTargetClosed(TARGET));
    }

    function test_Expiry_ExecuteRevertsExpired() public {
        (bytes memory data, bytes32 opId, uint48 readyAt) = _scheduleDelayedClose();
        vm.warp(uint256(readyAt) + EXPIRATION + 1 days);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerExpired.selector, opId));
        mgr.execute(diamond, data);
        assertFalse(mgr.isTargetClosed(TARGET));
    }

    /// @notice OZ `_isExpired` is `readyAt + expiration <= now`: the operation is expired at exactly that second.
    function test_Expiry_ExpiredAtExactBoundary() public {
        (bytes memory data, bytes32 opId, uint48 readyAt) = _scheduleDelayedClose();
        vm.warp(uint256(readyAt) + EXPIRATION);
        assertEq(mgr.getSchedule(opId), 0, "getSchedule reports expired");

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerExpired.selector, opId));
        mgr.setTargetClosed(TARGET, true);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerExpired.selector, opId));
        mgr.execute(diamond, data);

        // An expired operation may be scheduled again at the same second.
        vm.prank(admin);
        (bytes32 again,) = mgr.schedule(diamond, data, 0);
        assertEq(again, opId);
        assertEq(mgr.getSchedule(opId), block.timestamp + 1 days);
    }

    function test_Expiry_ValidOneSecondBeforeBoundary() public {
        (, bytes32 opId, uint48 readyAt) = _scheduleDelayedClose();
        vm.warp(uint256(readyAt) + EXPIRATION - 1);
        assertEq(mgr.getSchedule(opId), readyAt);

        vm.prank(admin);
        mgr.setTargetClosed(TARGET, true);
        assertTrue(mgr.isTargetClosed(TARGET));
        assertEq(mgr.getSchedule(opId), 0, "schedule consumed");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                #219: IMMEDIATE EXECUTE (OZ `execute` PARITY)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice With nothing scheduled, `execute` consumes nothing: it emits no `OperationExecuted` and returns 0,
    ///         even when the operation id kept a nonce from an earlier consumed schedule.
    function test_Execute_ImmediateEmitsNoOperationExecutedAndReturnsZero() public {
        (bytes memory data, bytes32 opId,) = _scheduleDelayedClose();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint32 consumedNonce = mgr.execute(diamond, data);
        assertGt(consumedNonce, 0);
        assertEq(mgr.getNonce(opId), consumedNonce);

        // Drop the admin delay so the same call becomes immediate.
        vm.prank(admin);
        mgr.setTargetAdminDelay(TARGET, 0);
        vm.warp(block.timestamp + MIN_SETBACK);
        assertEq(mgr.getTargetAdminDelay(TARGET), 0);

        vm.recordLogs();
        vm.prank(admin);
        uint32 nonce = mgr.execute(diamond, data);
        assertEq(nonce, 0, "nothing consumed");

        bytes32 sig = IAccessManager.OperationExecuted.selector;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != sig, "OperationExecuted emitted without a consumed schedule");
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //              #245: MUTATION PILOT REGRESSIONS (test/README.md)
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsInterface_IAccessManager() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IAccessManager).interfaceId));
    }

    /// @notice The init contract the recipe deploys only runs inside a diamond's initializing window.
    function test_InitOutsideInitializingWindowReverts() public {
        AccessManagerInit init = new AccessManagerInit();
        vm.expectRevert(NotInitializing.selector);
        init.init(alice);
    }

    function test_LockedRoles_RejectEveryRoleSetter() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerLockedRole.selector, ADMIN_ROLE));
        mgr.revokeRole(ADMIN_ROLE, admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerLockedRole.selector, ADMIN_ROLE));
        mgr.renounceRole(ADMIN_ROLE, admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerLockedRole.selector, ADMIN_ROLE));
        mgr.setRoleAdmin(ADMIN_ROLE, MINTER_ROLE);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerLockedRole.selector, ADMIN_ROLE));
        mgr.setRoleGuardian(ADMIN_ROLE, MINTER_ROLE);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerLockedRole.selector, ADMIN_ROLE));
        mgr.setGrantDelay(ADMIN_ROLE, 1 days);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerLockedRole.selector, PUBLIC_ROLE));
        mgr.labelRole(PUBLIC_ROLE, "PUBLIC");
        vm.stopPrank();

        (bool isMember,) = mgr.hasRole(ADMIN_ROLE, admin);
        assertTrue(isMember, "admin kept ADMIN_ROLE");
    }

    function test_RoleSetters_NonAdminReverts() public {
        bytes memory unauthorized =
            abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedAccount.selector, alice, ADMIN_ROLE);
        vm.startPrank(alice);
        vm.expectRevert(unauthorized);
        mgr.setRoleAdmin(MINTER_ROLE, 2);
        vm.expectRevert(unauthorized);
        mgr.setRoleGuardian(MINTER_ROLE, 2);
        vm.expectRevert(unauthorized);
        mgr.setGrantDelay(MINTER_ROLE, 1 days);
        vm.expectRevert(unauthorized);
        mgr.labelRole(MINTER_ROLE, "MINTER");
        vm.stopPrank();
    }

    /// @notice A pending grant-delay change that has not taken effect is replaced, measured from the delay in force.
    function test_SetGrantDelay_ReplacesPendingChange() public {
        vm.prank(admin);
        mgr.setGrantDelay(MINTER_ROLE, 10 days);
        vm.warp(block.timestamp + 1 days);

        uint48 effectAt = uint48(block.timestamp + MIN_SETBACK);
        vm.expectEmit(true, false, false, true, diamond);
        emit IAccessManager.RoleGrantDelayChanged(MINTER_ROLE, 1 days, effectAt);
        vm.prank(admin);
        mgr.setGrantDelay(MINTER_ROLE, 1 days);

        assertEq(mgr.getRoleGrantDelay(MINTER_ROLE), 0, "the 10-day change never landed");
        vm.warp(effectAt);
        assertEq(mgr.getRoleGrantDelay(MINTER_ROLE), 1 days);
    }

    /// @notice A decrease larger than MIN_SETBACK waits out the exact difference.
    function test_SetGrantDelay_LargeDecreaseWaitsForTheDifference() public {
        vm.prank(admin);
        mgr.setGrantDelay(MINTER_ROLE, 30 days);
        vm.warp(block.timestamp + MIN_SETBACK);
        assertEq(mgr.getRoleGrantDelay(MINTER_ROLE), 30 days);

        uint48 effectAt = uint48(block.timestamp + 29 days);
        vm.expectEmit(true, false, false, true, diamond);
        emit IAccessManager.RoleGrantDelayChanged(MINTER_ROLE, 1 days, effectAt);
        vm.prank(admin);
        mgr.setGrantDelay(MINTER_ROLE, 1 days);

        vm.warp(effectAt - 1);
        assertEq(mgr.getRoleGrantDelay(MINTER_ROLE), 30 days);
        vm.warp(effectAt);
        assertEq(mgr.getRoleGrantDelay(MINTER_ROLE), 1 days);
    }

    /// @notice Re-granting a member updates only the execution delay: `since` is kept, and the event's `since` is
    ///         when the new delay takes effect (now, for an increase), as in OZ.
    function test_GrantRole_RegrantUpdatesDelayKeepsSince() public {
        uint48 since = uint48(block.timestamp);
        vm.expectEmit(true, true, false, true, diamond);
        emit IAccessManager.RoleGranted(MINTER_ROLE, alice, 0, since, true);
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 0);

        vm.warp(block.timestamp + 1 days);
        vm.expectEmit(true, true, false, true, diamond);
        emit IAccessManager.RoleGranted(MINTER_ROLE, alice, 2 days, uint48(block.timestamp), false);
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 2 days);

        (uint48 since_, uint32 delay,,) = mgr.getAccess(MINTER_ROLE, alice);
        assertEq(since_, since, "since kept");
        assertEq(delay, 2 days, "delay updated");
        assertEq(mgr.getRoleMemberCount(MINTER_ROLE), 1);
    }

    /// @notice OZ `_grantRole` emits {RoleGranted} for every grant to an existing member, an unchanged delay included.
    function test_GrantRole_RegrantSameDelayEmitsRoleGranted() public {
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 1 days);
        vm.warp(block.timestamp + 1 hours);

        vm.expectEmit(true, true, false, true, diamond);
        emit IAccessManager.RoleGranted(MINTER_ROLE, alice, 1 days, uint48(block.timestamp), false);
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 1 days);
        _assertAccess(alice, 1 days, 0, 0);
    }

    function test_RevokeRole_NonMemberEmitsNothing() public {
        vm.recordLogs();
        vm.prank(admin);
        mgr.revokeRole(MINTER_ROLE, alice);
        _assertNoLog(IAccessManager.RoleRevoked.selector);
    }

    function test_RevokeRole_RemovesFromMemberSet() public {
        vm.startPrank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 0);
        mgr.grantRole(MINTER_ROLE, bob, 0);
        mgr.revokeRole(MINTER_ROLE, alice);
        vm.stopPrank();

        address[] memory members = mgr.getRoleMembers(MINTER_ROLE);
        assertEq(members.length, 1);
        assertEq(members[0], bob);
    }

    function test_Schedule_TwiceRevertsAlreadyScheduled() public {
        (CallSink sink, bytes memory data) = _delayedMinterSink();
        vm.prank(alice);
        (bytes32 opId,) = mgr.schedule(address(sink), data, 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerAlreadyScheduled.selector, opId));
        mgr.schedule(address(sink), data, 0);
    }

    function test_Cancel_UnscheduledReverts() public {
        (CallSink sink, bytes memory data) = _delayedMinterSink();
        bytes32 opId = mgr.hashOperation(alice, address(sink), data);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, opId));
        mgr.cancel(alice, address(sink), data);
    }

    /// @notice A cancelled operation is gone, not merely expired: executing it reverts NotScheduled.
    function test_Cancel_ThenExecuteRevertsNotScheduled() public {
        (CallSink sink, bytes memory data) = _delayedMinterSink();
        vm.prank(alice);
        (bytes32 opId,) = mgr.schedule(address(sink), data, 0);
        vm.prank(alice);
        mgr.cancel(alice, address(sink), data);

        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, opId));
        mgr.execute(address(sink), data);
    }

    /// @notice Nonces count up across operations, and cancel reports the cancelled operation's own nonce.
    function test_Cancel_ReturnsAndEmitsTheOperationNonce() public {
        (CallSink sink, bytes memory data) = _delayedMinterSink();
        bytes memory data2 = abi.encodeCall(CallSink.ping, (43));
        vm.startPrank(alice);
        mgr.schedule(address(sink), data, 0);
        (bytes32 opId2, uint32 nonce2) = mgr.schedule(address(sink), data2, 0);
        assertEq(nonce2, 2);
        assertEq(mgr.getNonce(opId2), 2);

        vm.expectEmit(true, true, false, false, diamond);
        emit IAccessManager.OperationCanceled(opId2, 2);
        uint32 cancelled = mgr.cancel(alice, address(sink), data2);
        vm.stopPrank();
        assertEq(cancelled, 2);
    }

    function test_Execute_ReturnsTheConsumedOperationNonce() public {
        (CallSink sink, bytes memory data) = _delayedMinterSink();
        bytes memory data2 = abi.encodeCall(CallSink.ping, (43));
        vm.startPrank(alice);
        mgr.schedule(address(sink), data, 0);
        (bytes32 opId2,) = mgr.schedule(address(sink), data2, 0);
        vm.warp(block.timestamp + 1 days);

        vm.expectEmit(true, true, false, false, diamond);
        emit IAccessManager.OperationExecuted(opId2, 2);
        uint32 nonce = mgr.execute(address(sink), data2);
        vm.stopPrank();
        assertEq(nonce, 2);
    }

    /// @notice Calldata too short for a selector is refused with the typed error, naming ADMIN_ROLE.
    function test_Execute_SelfWithoutSelectorReverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedAccount.selector, admin, ADMIN_ROLE)
        );
        mgr.execute(diamond, hex"");
    }

    /// @notice Closing the manager blocks its unrestricted selectors through `execute`, even for the admin.
    function test_ClosedManager_BlocksUnrestrictedSelfCall() public {
        vm.prank(admin);
        mgr.setTargetClosed(diamond, true);

        bytes memory data = abi.encodeCall(IAccessManager.getNonce, (bytes32(0)));
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedAccount.selector, admin, ADMIN_ROLE)
        );
        mgr.execute(diamond, data);
    }

    /// @notice An unauthorized self-`execute` of `grantRole` reports the granted role's admin, not ADMIN_ROLE.
    function test_Execute_SelfGrantRoleReportsRoleAdmin() public {
        uint64 SUPER_ROLE = 5;
        vm.prank(admin);
        mgr.setRoleAdmin(MINTER_ROLE, SUPER_ROLE);

        bytes memory data = abi.encodeCall(IAccessManager.grantRole, (MINTER_ROLE, alice, 0));
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedAccount.selector, bob, SUPER_ROLE)
        );
        mgr.execute(diamond, data);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //          #287: RE-GRANT EXECUTION DELAY (OZ `withUpdate(delay, 0)`)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Re-granting a lower execution delay waits out the difference: the old delay binds until `effectAt`.
    function test_GrantRole_RegrantDecreaseWaitsOutTheDifference() public {
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 7 days);
        uint48 since = uint48(block.timestamp);
        vm.warp(block.timestamp + 1 days);

        uint48 effectAt = uint48(block.timestamp + 5 days);
        vm.expectEmit(true, true, false, true, diamond);
        emit IAccessManager.RoleGranted(MINTER_ROLE, alice, 2 days, effectAt, false);
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 2 days);

        (uint48 since_, uint32 current, uint32 pending, uint48 effect) = mgr.getAccess(MINTER_ROLE, alice);
        assertEq(since_, since, "since kept");
        assertEq(current, 7 days, "old delay still current");
        assertEq(pending, 2 days, "new delay pending");
        assertEq(effect, effectAt, "effect time");

        vm.warp(effectAt - 1);
        (, uint32 delay) = mgr.hasRole(MINTER_ROLE, alice);
        assertEq(delay, 7 days, "old delay binds until effectAt");

        vm.warp(effectAt);
        (, delay) = mgr.hasRole(MINTER_ROLE, alice);
        assertEq(delay, 2 days, "new delay from effectAt");
        _assertAccess(alice, 2 days, 0, 0);
    }

    /// @notice Re-granting a higher execution delay takes effect at once.
    function test_GrantRole_RegrantIncreaseIsImmediate() public {
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 1 days);
        vm.warp(block.timestamp + 1 days);

        vm.expectEmit(true, true, false, true, diamond);
        emit IAccessManager.RoleGranted(MINTER_ROLE, alice, 3 days, uint48(block.timestamp), false);
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 3 days);

        (, uint32 delay) = mgr.hasRole(MINTER_ROLE, alice);
        assertEq(delay, 3 days);
        _assertAccess(alice, 3 days, 0, 0);
    }

    /// @notice A re-grant replaces a pending decrease, measured from the delay still in force; re-granting that
    ///         delay cancels the pending one.
    function test_GrantRole_RegrantReplacesPendingDecrease() public {
        vm.startPrank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 10 days);
        mgr.grantRole(MINTER_ROLE, alice, 2 days); // pending: 2 days, in force 8 days from now
        uint48 firstEffect = uint48(block.timestamp + 8 days);
        vm.warp(block.timestamp + 1 days);

        uint48 effectAt = uint48(block.timestamp + 5 days);
        vm.expectEmit(true, true, false, true, diamond);
        emit IAccessManager.RoleGranted(MINTER_ROLE, alice, 5 days, effectAt, false);
        mgr.grantRole(MINTER_ROLE, alice, 5 days);
        _assertAccess(alice, 10 days, 5 days, effectAt);

        vm.warp(effectAt);
        (, uint32 delay) = mgr.hasRole(MINTER_ROLE, alice);
        assertEq(delay, 5 days);
        vm.warp(firstEffect);
        (, delay) = mgr.hasRole(MINTER_ROLE, alice);
        assertEq(delay, 5 days, "the replaced 2-day delay never lands");

        // A new pending decrease, then a re-grant of the delay in force: nothing stays pending.
        mgr.grantRole(MINTER_ROLE, alice, 1 days);
        _assertAccess(alice, 5 days, 1 days, uint48(block.timestamp + 4 days));
        mgr.grantRole(MINTER_ROLE, alice, 5 days);
        vm.stopPrank();
        _assertAccess(alice, 5 days, 0, 0);
        vm.warp(block.timestamp + 4 days);
        (, delay) = mgr.hasRole(MINTER_ROLE, alice);
        assertEq(delay, 5 days, "the cancelled decrease never lands");
    }

    /// @notice Revoking drops a pending decrease with the rest of the access: a later grant starts fresh.
    function test_GrantRole_RevokeClearsPendingDecrease() public {
        vm.startPrank(admin);
        mgr.grantRole(MINTER_ROLE, alice, 7 days);
        mgr.grantRole(MINTER_ROLE, alice, 0);
        mgr.revokeRole(MINTER_ROLE, alice);
        (uint48 since, uint32 current, uint32 pending, uint48 effect) = mgr.getAccess(MINTER_ROLE, alice);
        assertEq(since + current + pending + effect, 0);

        mgr.grantRole(MINTER_ROLE, alice, 3 days);
        vm.stopPrank();
        _assertAccess(alice, 3 days, 0, 0);
    }

    /// @notice `canCall`, `schedule` and `execute` keep enforcing the old delay until a decrease is in force.
    function test_GrantRole_PendingDecreaseBindsCanCallAndExecute() public {
        CallSink sink = new CallSink();
        vm.startPrank(admin);
        mgr.setTargetFunctionRole(address(sink), _selectors(CallSink.ping.selector), MINTER_ROLE);
        mgr.grantRole(MINTER_ROLE, alice, 2 days);
        mgr.grantRole(MINTER_ROLE, alice, 0);
        vm.stopPrank();
        uint48 effectAt = uint48(block.timestamp + 2 days);
        bytes memory data = abi.encodeCall(CallSink.ping, (42));
        bytes32 opId = mgr.hashOperation(alice, address(sink), data);
        bytes memory scheduled = abi.encodeCall(CallSink.ping, (43));

        (bool immediate, uint32 delay) = mgr.canCall(alice, address(sink), CallSink.ping.selector);
        assertFalse(immediate);
        assertEq(delay, 2 days, "old delay binds");

        vm.startPrank(alice);
        (bytes32 scheduledId, uint32 nonce) = mgr.schedule(address(sink), scheduled, 0);
        assertEq(mgr.getSchedule(scheduledId), effectAt, "scheduled under the old delay");

        vm.warp(effectAt - 1);
        (immediate, delay) = mgr.canCall(alice, address(sink), CallSink.ping.selector);
        assertFalse(immediate);
        assertEq(delay, 2 days);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, opId));
        mgr.execute(address(sink), data);

        vm.warp(effectAt);
        (immediate, delay) = mgr.canCall(alice, address(sink), CallSink.ping.selector);
        assertTrue(immediate);
        assertEq(delay, 0);
        assertEq(mgr.execute(address(sink), data), 0, "immediate: nothing to consume");
        assertEq(mgr.execute(address(sink), scheduled), nonce, "the matured schedule is still spent");
        vm.stopPrank();
        assertEq(mgr.getSchedule(scheduledId), 0);
    }

    /// @notice The re-grant follows OZ `Time.Delay.withUpdate(newDelay, 0)` for any old delay, new delay and gap.
    function testFuzz_GrantRole_RegrantMatchesWithUpdate(uint32 oldDelay, uint32 newDelay, uint32 gap) public {
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, oldDelay);
        vm.warp(block.timestamp + gap);

        uint48 effectAt = uint48(block.timestamp + (oldDelay > newDelay ? oldDelay - newDelay : 0));
        vm.expectEmit(true, true, false, true, diamond);
        emit IAccessManager.RoleGranted(MINTER_ROLE, alice, newDelay, effectAt, false);
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, newDelay);

        (, uint32 delay) = mgr.hasRole(MINTER_ROLE, alice);
        if (effectAt > block.timestamp) {
            _assertAccess(alice, oldDelay, newDelay, effectAt);
            assertEq(delay, oldDelay);
            vm.warp(effectAt - 1);
            (, delay) = mgr.hasRole(MINTER_ROLE, alice);
            assertEq(delay, oldDelay);
            vm.warp(effectAt);
            (, delay) = mgr.hasRole(MINTER_ROLE, alice);
        }
        assertEq(delay, newDelay);
        _assertAccess(alice, newDelay, 0, 0);
    }

    /// @dev Asserts `account`'s MINTER_ROLE delay fields as `getAccess` reports them now.
    function _assertAccess(address account, uint32 current, uint32 pending, uint48 effect) internal view {
        (, uint32 current_, uint32 pending_, uint48 effect_) = mgr.getAccess(MINTER_ROLE, account);
        assertEq(current_, current, "current delay");
        assertEq(pending_, pending, "pending delay");
        assertEq(effect_, effect, "effect time");
    }

    /// @dev A CallSink whose `ping` needs MINTER_ROLE, held by alice with a 1-day execution delay.
    function _delayedMinterSink() internal returns (CallSink sink, bytes memory data) {
        sink = new CallSink();
        vm.startPrank(admin);
        mgr.setTargetFunctionRole(address(sink), _selectors(CallSink.ping.selector), MINTER_ROLE);
        mgr.grantRole(MINTER_ROLE, alice, 1 days);
        vm.stopPrank();
        data = abi.encodeCall(CallSink.ping, (42));
    }

    function _assertNoLog(bytes32 sig) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != sig, "unexpected event");
        }
    }
}
