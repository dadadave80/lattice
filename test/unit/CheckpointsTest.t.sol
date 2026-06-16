// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Checkpoints} from "@lattice/utils/libraries/Checkpoints.sol";
import {Test} from "forge-std/Test.sol";

/// @title CheckpointsHarness
/// @notice Exposes Checkpoints library functions for testing.
contract CheckpointsHarness {
    Checkpoints.Trace208 private _trace;

    function push(uint48 key, uint208 value) external returns (uint208 prev, uint208 next) {
        return Checkpoints.push(_trace, key, value);
    }

    function lowerLookup(uint48 key) external view returns (uint208) {
        return Checkpoints.lowerLookup(_trace, key);
    }

    function upperLookup(uint48 key) external view returns (uint208) {
        return Checkpoints.upperLookup(_trace, key);
    }

    function upperLookupRecent(uint48 key) external view returns (uint208) {
        return Checkpoints.upperLookupRecent(_trace, key);
    }

    function latest() external view returns (uint208) {
        return Checkpoints.latest(_trace);
    }

    function latestCheckpoint() external view returns (bool exists, uint48 key, uint208 value) {
        return Checkpoints.latestCheckpoint(_trace);
    }

    function length() external view returns (uint256) {
        return Checkpoints.length(_trace);
    }

    function at(uint32 pos) external view returns (Checkpoints.Checkpoint208 memory) {
        return Checkpoints.at(_trace, pos);
    }
}

/// @title CheckpointsTest
contract CheckpointsTest is Test {
    CheckpointsHarness harness;

    function setUp() public {
        harness = new CheckpointsHarness();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            EMPTY TRACE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_EmptyTrace_LatestReturnsZero() public view {
        assertEq(harness.latest(), 0);
    }

    function test_EmptyTrace_UpperLookupReturnsZero() public view {
        assertEq(harness.upperLookup(100), 0);
    }

    function test_EmptyTrace_LowerLookupReturnsZero() public view {
        assertEq(harness.lowerLookup(100), 0);
    }

    function test_EmptyTrace_UpperLookupRecentReturnsZero() public view {
        assertEq(harness.upperLookupRecent(100), 0);
    }

    function test_EmptyTrace_LatestCheckpointReturnsFalse() public view {
        (bool exists, uint48 key, uint208 value) = harness.latestCheckpoint();
        assertFalse(exists);
        assertEq(key, 0);
        assertEq(value, 0);
    }

    function test_EmptyTrace_LengthIsZero() public view {
        assertEq(harness.length(), 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           PUSH MONOTONIC KEYS
    //////////////////////////////////////////////////////////////////////////*//

    function test_PushMonotonicKeys_StoresValues() public {
        harness.push(10, 100);
        harness.push(20, 200);
        harness.push(30, 300);

        assertEq(harness.latest(), 300);
        assertEq(harness.length(), 3);
    }

    function test_PushFirst_ReturnsPrevZero() public {
        (uint208 prev, uint208 next) = harness.push(1, 42);
        assertEq(prev, 0);
        assertEq(next, 42);
    }

    function test_PushSecond_ReturnsPrevFromFirst() public {
        harness.push(1, 42);
        (uint208 prev, uint208 next) = harness.push(2, 99);
        assertEq(prev, 42);
        assertEq(next, 99);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           PUSH SAME KEY (REPLACE)
    //////////////////////////////////////////////////////////////////////////*//

    function test_PushSameKey_ReplacesValue() public {
        harness.push(10, 100);
        (uint208 prev, uint208 next) = harness.push(10, 999);
        assertEq(prev, 100);
        assertEq(next, 999);

        // Length should stay the same after replace
        assertEq(harness.length(), 1);
        assertEq(harness.latest(), 999);
    }

    function test_PushSameKeyMultipleTimes_AlwaysReplaces() public {
        harness.push(5, 10);
        harness.push(5, 20);
        harness.push(5, 30);

        assertEq(harness.length(), 1);
        assertEq(harness.latest(), 30);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       PUSH DECREASING KEY (REVERT)
    //////////////////////////////////////////////////////////////////////////*//

    function test_PushDecreasingKey_RevertsUnorderedInsertion() public {
        harness.push(20, 200);
        vm.expectRevert(abi.encodeWithSelector(Checkpoints.CheckpointUnorderedInsertion.selector));
        harness.push(10, 100);
    }

    function test_PushDecreasingKeyFromZero_Reverts() public {
        // key = 0 is valid first insert; then key = 0 again should replace, not revert
        harness.push(0, 1);
        harness.push(0, 2); // same key — replace, no revert
        assertEq(harness.latest(), 2);

        // Pushing a lower key after 0 isn't possible (uint48, no negatives)
        // but pushing 5 then 3 should revert
        harness.push(5, 50);
        vm.expectRevert(abi.encodeWithSelector(Checkpoints.CheckpointUnorderedInsertion.selector));
        harness.push(3, 30);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           UPPER LOOKUP TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_UpperLookup_ExactKeyMatch() public {
        harness.push(10, 100);
        harness.push(20, 200);
        harness.push(30, 300);

        assertEq(harness.upperLookup(10), 100);
        assertEq(harness.upperLookup(20), 200);
        assertEq(harness.upperLookup(30), 300);
    }

    function test_UpperLookup_KeyBetweenCheckpoints() public {
        harness.push(10, 100);
        harness.push(30, 300);

        // Key 20 is between 10 and 30 — should return the value at key 10
        assertEq(harness.upperLookup(20), 100);
    }

    function test_UpperLookup_KeyBeforeFirstCheckpoint() public {
        harness.push(10, 100);

        // Key 5 is before first checkpoint — returns 0
        assertEq(harness.upperLookup(5), 0);
    }

    function test_UpperLookup_KeyAfterLastCheckpoint() public {
        harness.push(10, 100);
        harness.push(20, 200);

        // Key 100 is after last checkpoint — returns last value
        assertEq(harness.upperLookup(100), 200);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       UPPER LOOKUP RECENT TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_UpperLookupRecent_MatchesUpperLookupForSparseData() public {
        harness.push(100, 1000);
        harness.push(200, 2000);
        harness.push(300, 3000);

        assertEq(harness.upperLookupRecent(100), harness.upperLookup(100));
        assertEq(harness.upperLookupRecent(150), harness.upperLookup(150));
        assertEq(harness.upperLookupRecent(200), harness.upperLookup(200));
        assertEq(harness.upperLookupRecent(250), harness.upperLookup(250));
        assertEq(harness.upperLookupRecent(300), harness.upperLookup(300));
        assertEq(harness.upperLookupRecent(50), harness.upperLookup(50));
        assertEq(harness.upperLookupRecent(400), harness.upperLookup(400));
    }

    function test_UpperLookupRecent_ManyCheckpointsMatchesUpperLookup() public {
        // Push enough to exercise the window-doubling path (> 5 checkpoints)
        for (uint48 i = 1; i <= 20; ++i) {
            harness.push(i * 10, uint208(i * 100));
        }

        // Test at various points
        assertEq(harness.upperLookupRecent(5), harness.upperLookup(5)); // before first
        assertEq(harness.upperLookupRecent(10), harness.upperLookup(10)); // exact first
        assertEq(harness.upperLookupRecent(105), harness.upperLookup(105)); // middle
        assertEq(harness.upperLookupRecent(200), harness.upperLookup(200)); // exact middle
        assertEq(harness.upperLookupRecent(190), harness.upperLookup(190)); // near middle
        assertEq(harness.upperLookupRecent(200), harness.upperLookup(200)); // exact recent
        assertEq(harness.upperLookupRecent(195), harness.upperLookup(195)); // just before recent
        assertEq(harness.upperLookupRecent(999), harness.upperLookup(999)); // after last
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          LATEST CHECKPOINT TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_LatestCheckpoint_ReturnsTrueWhenNonEmpty() public {
        harness.push(42, 7777);
        (bool exists, uint48 key, uint208 value) = harness.latestCheckpoint();
        assertTrue(exists);
        assertEq(key, 42);
        assertEq(value, 7777);
    }

    function test_LatestCheckpoint_ReflectsLatestPush() public {
        harness.push(1, 10);
        harness.push(2, 20);
        (, uint48 key, uint208 value) = harness.latestCheckpoint();
        assertEq(key, 2);
        assertEq(value, 20);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              AT TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_At_ReturnsCorrectCheckpointByIndex() public {
        harness.push(10, 100);
        harness.push(20, 200);
        harness.push(30, 300);

        Checkpoints.Checkpoint208 memory cp0 = harness.at(0);
        assertEq(cp0._key, 10);
        assertEq(cp0._value, 100);

        Checkpoints.Checkpoint208 memory cp2 = harness.at(2);
        assertEq(cp2._key, 30);
        assertEq(cp2._value, 300);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           LOWER LOOKUP TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_LowerLookup_ExactKeyMatch() public {
        harness.push(10, 100);
        harness.push(20, 200);

        assertEq(harness.lowerLookup(10), 100);
        assertEq(harness.lowerLookup(20), 200);
    }

    function test_LowerLookup_KeyBetweenCheckpoints() public {
        harness.push(10, 100);
        harness.push(30, 300);

        // Key 15 is between 10 and 30 — lowerLookup returns first checkpoint >= key, i.e. 30
        assertEq(harness.lowerLookup(15), 300);
    }

    function test_LowerLookup_KeyAfterLastCheckpoint_ReturnsZero() public {
        harness.push(10, 100);
        // Key 100 is after the last checkpoint — no checkpoint with key >= 100
        assertEq(harness.lowerLookup(100), 0);
    }

    function test_LowerLookup_KeyExactlyAtLast() public {
        harness.push(10, 100);
        assertEq(harness.lowerLookup(10), 100);
        assertEq(harness.lowerLookup(11), 0);
    }
}
