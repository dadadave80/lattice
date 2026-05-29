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
}
