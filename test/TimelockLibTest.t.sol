// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TimelockLib} from "@lattice/utils/libraries/TimelockLib.sol";
import {Test} from "forge-std/Test.sol";

contract TimelockHarness {
    using TimelockLib for TimelockLib.SingleSchedule;
    using TimelockLib for TimelockLib.MultiSchedule;

    TimelockLib.SingleSchedule internal _single;
    TimelockLib.MultiSchedule internal _multi;

    function scheduleSingle(uint48 delay) external returns (uint48) {
        return _single.schedule(delay);
    }

    function rescheduleSingle(uint48 newReadyAt) external {
        _single.reschedule(newReadyAt);
    }

    function consumeSingle() external {
        _single.consume();
    }

    function cancelSingle() external {
        _single.cancel();
    }

    function readyAtSingle() external view returns (uint48) {
        return _single.readyAt();
    }

    function isPendingSingle() external view returns (bool) {
        return _single.isPending();
    }

    function isReadySingle() external view returns (bool) {
        return _single.isReady();
    }

    function scheduleMulti(bytes32 id, uint48 delay) external returns (uint48) {
        return _multi.schedule(id, delay);
    }

    function rescheduleMulti(bytes32 id, uint48 newReadyAt) external {
        _multi.reschedule(id, newReadyAt);
    }

    function consumeMulti(bytes32 id) external {
        _multi.consume(id);
    }

    function cancelMulti(bytes32 id) external {
        _multi.cancel(id);
    }

    function readyAtMulti(bytes32 id) external view returns (uint48) {
        return _multi.readyAt(id);
    }

    function isPendingMulti(bytes32 id) external view returns (bool) {
        return _multi.isPending(id);
    }

    function isReadyMulti(bytes32 id) external view returns (bool) {
        return _multi.isReady(id);
    }
}

contract TimelockLibTest is Test {
    TimelockHarness internal h;

    function setUp() public {
        h = new TimelockHarness();
        vm.warp(1_000_000);
    }

    function test_SingleScheduleSetsReadyAtToNowPlusDelay() public {
        uint48 readyAt = h.scheduleSingle(60);
        assertEq(readyAt, uint48(block.timestamp + 60));
        assertEq(h.readyAtSingle(), readyAt);
        assertTrue(h.isPendingSingle());
        assertFalse(h.isReadySingle());
    }

    function test_SingleConsumeAfterDelayClearsReadyAt() public {
        h.scheduleSingle(60);
        vm.warp(block.timestamp + 60);
        h.consumeSingle();
        assertEq(h.readyAtSingle(), 0);
        assertFalse(h.isPendingSingle());
    }

    function test_SingleConsumeBeforeReadyReverts() public {
        h.scheduleSingle(60);
        uint48 expectedReady = uint48(block.timestamp + 60);
        vm.expectRevert(
            abi.encodeWithSelector(TimelockLib.TimelockNotReady.selector, expectedReady, uint48(block.timestamp))
        );
        h.consumeSingle();
    }

    function test_SingleConsumeWithoutPendingReverts() public {
        vm.expectRevert(TimelockLib.TimelockNotPending.selector);
        h.consumeSingle();
    }

    function test_SingleCancelClearsReadyAt() public {
        h.scheduleSingle(60);
        h.cancelSingle();
        assertEq(h.readyAtSingle(), 0);
        assertFalse(h.isPendingSingle());
    }

    function test_SingleCancelWithoutPendingReverts() public {
        vm.expectRevert(TimelockLib.TimelockNotPending.selector);
        h.cancelSingle();
    }

    function test_SingleDoubleScheduleReverts() public {
        uint48 firstReady = h.scheduleSingle(60);
        vm.expectRevert(abi.encodeWithSelector(TimelockLib.TimelockAlreadyPending.selector, firstReady));
        h.scheduleSingle(120);
    }

    function test_SingleRescheduleOverwritesReadyAt() public {
        h.scheduleSingle(60);
        uint48 newReady = uint48(block.timestamp + 5);
        h.rescheduleSingle(newReady);
        assertEq(h.readyAtSingle(), newReady);
    }

    function test_SingleRescheduleWithoutPendingReverts() public {
        vm.expectRevert(TimelockLib.TimelockNotPending.selector);
        h.rescheduleSingle(uint48(block.timestamp + 5));
    }

    function test_SingleIsReadyAtExactReadyAt() public {
        h.scheduleSingle(60);
        vm.warp(block.timestamp + 60);
        assertTrue(h.isReadySingle());
    }
}
