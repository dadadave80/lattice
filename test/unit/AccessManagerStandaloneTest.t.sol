// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessManagerStandalone} from "@lattice/access/AccessManagerStandalone.sol";
import {IAccessManager} from "@lattice/interfaces/access/IAccessManager.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Minimal call target used by schedule/execute tests.
contract CallSink {
    uint256 public value;

    function setValue(uint256 v) external {
        value = v;
    }
}

contract AccessManagerStandaloneTest is Test {
    uint64 constant ADMIN_ROLE = 0;
    uint64 constant MINTER_ROLE = 1;

    AccessManagerStandalone internal mgr;
    address internal admin = address(0xA1);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        vm.warp(1_000_000);
        mgr = new AccessManagerStandalone(admin);
    }

    function test_DeploysAndAdminIsSet() public view {
        (bool isMember,) = mgr.hasRole(ADMIN_ROLE, admin);
        assertTrue(isMember);
    }

    /// @notice An operation scheduled by a delayed role can be executed after the delay elapses.
    function test_ScheduleAndExecute() public {
        CallSink sink = new CallSink();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sink.setValue.selector;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(sink), selectors, MINTER_ROLE);
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, uint32(1 days));

        bytes memory data = abi.encodeCall(CallSink.setValue, (42));

        vm.prank(alice);
        (bytes32 opId, uint32 nonce) = mgr.schedule(address(sink), data, uint48(block.timestamp + 1 days));
        assertGt(uint256(opId), 0);
        assertEq(nonce, 1);

        // Too early — not yet ready.
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotReady.selector, opId));
        vm.prank(alice);
        mgr.execute(address(sink), data);

        // After the delay the operation executes and the schedule is consumed.
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        mgr.execute(address(sink), data);

        assertEq(sink.value(), 42);
        assertEq(mgr.getSchedule(opId), 0);
    }

    /// @notice The original caller can cancel a pending operation, clearing its schedule.
    function test_CancelOperation() public {
        CallSink sink = new CallSink();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sink.setValue.selector;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(sink), selectors, MINTER_ROLE);
        vm.prank(admin);
        mgr.grantRole(MINTER_ROLE, alice, uint32(1 days));

        bytes memory data = abi.encodeCall(CallSink.setValue, (42));
        vm.prank(alice);
        (bytes32 opId,) = mgr.schedule(address(sink), data, uint48(block.timestamp + 1 days));
        assertGt(mgr.getSchedule(opId), 0);

        vm.prank(alice);
        mgr.cancel(alice, address(sink), data);

        assertEq(mgr.getSchedule(opId), 0);
    }

    /// @notice Scheduling without the required role reverts with AccessManagerUnauthorizedAccount.
    function test_UnauthorizedScheduleReverts() public {
        CallSink sink = new CallSink();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sink.setValue.selector;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(sink), selectors, MINTER_ROLE);

        bytes memory data = abi.encodeCall(CallSink.setValue, (42));
        // Alice was never granted MINTER_ROLE.
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedAccount.selector, alice, MINTER_ROLE)
        );
        mgr.schedule(address(sink), data, uint48(block.timestamp + 1 days));
    }
}
