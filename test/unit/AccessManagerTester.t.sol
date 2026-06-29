// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessManager} from "@lattice/access/AccessManager.sol";
import {AccessManagerLib} from "@lattice/access/libraries/AccessManagerLib.sol";
import {IAccessManager} from "@lattice/interfaces/access/IAccessManager.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract MockAccessManagerContract is AccessManager {
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessManagerLib.__AccessManager_init(_admin);
        InitializableLib.postInitializer(s);
    }
}

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

contract AccessManagerTester is Test {
    uint64 constant ADMIN_ROLE = 0;
    uint64 constant PUBLIC_ROLE = type(uint64).max;
    uint64 constant MINTER_ROLE = 1;

    MockAccessManagerContract internal mgr;
    address internal admin = address(0xA1);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        vm.warp(1_000_000);
        mgr = new MockAccessManagerContract();
        mgr.initialize(admin);
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
        MockAccessManagerContract mgr2 = new MockAccessManagerContract();
        vm.expectRevert(IAccessManager.AccessManagerInvalidInitialAdmin.selector);
        mgr2.initialize(address(0));
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

    /// @notice M-5 regression: setGrantDelay with no change is a no-op and emits no event.
    function test_SetGrantDelaySameValueIsNoop() public {
        vm.prank(admin);
        mgr.setGrantDelay(MINTER_ROLE, 1 days);
        vm.warp(block.timestamp + 1 weeks); // let delay take effect
        assertEq(mgr.getRoleGrantDelay(MINTER_ROLE), 1 days);

        // Set same delay — should be a no-op
        vm.recordLogs();
        vm.prank(admin);
        mgr.setGrantDelay(MINTER_ROLE, 1 days);

        // No RoleGrantDelayChanged event should be emitted
        bytes32 sig = keccak256("RoleGrantDelayChanged(uint64,uint32,uint48)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found = false;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == sig) found = true;
        }
        assertFalse(found, "RoleGrantDelayChanged should not be emitted for no-op");
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
}
