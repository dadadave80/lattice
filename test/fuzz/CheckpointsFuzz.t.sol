// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Checkpoints} from "@lattice/utils/libraries/Checkpoints.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Thin harness exposing the Checkpoints library for fuzz testing.
contract CheckpointsHarness2 {
    Checkpoints.Trace208 private _trace;

    function push(uint48 key, uint208 value) external returns (uint208 prev, uint208 next) {
        return Checkpoints.push(_trace, key, value);
    }

    function upperLookup(uint48 key) external view returns (uint208) {
        return Checkpoints.upperLookup(_trace, key);
    }

    function lowerLookup(uint48 key) external view returns (uint208) {
        return Checkpoints.lowerLookup(_trace, key);
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

/// @title CheckpointsFuzz
contract CheckpointsFuzz is Test {
    CheckpointsHarness2 harness;

    function setUp() public {
        harness = new CheckpointsHarness2();
    }

    // -------------------------------------------------------------------------
    // Monotonic push
    // -------------------------------------------------------------------------

    /// @notice Pushing 8 checkpoints with non-decreasing keys always succeeds,
    ///         and `latest()` always reflects the last pushed value.
    function testFuzz_PushMonotonicTimestamps(uint48[8] memory keys, uint208[8] memory values) public {
        // Sort keys to be non-decreasing; use bound to keep them in a sane range.
        for (uint256 i; i < 8; ++i) {
            keys[i] = uint48(bound(uint256(keys[i]), 0, type(uint48).max));
        }
        // Make keys non-decreasing.
        for (uint256 i = 1; i < 8; ++i) {
            if (keys[i] < keys[i - 1]) {
                keys[i] = keys[i - 1];
            }
        }

        // Push all 8 checkpoints — none should revert.
        for (uint256 i; i < 8; ++i) {
            harness.push(keys[i], values[i]);
        }

        // `latest()` must equal the last pushed value.
        assertEq(harness.latest(), values[7], "latest must equal the last pushed value");
    }

    // -------------------------------------------------------------------------
    // upperLookup exact-key semantics
    // -------------------------------------------------------------------------

    /// @notice upperLookup at the exact key of a checkpoint returns that checkpoint's value.
    function testFuzz_UpperLookupEqualsLowerForExactMatch(uint48 k1, uint48 k2) public {
        // Ensure strictly increasing keys.
        k1 = uint48(bound(uint256(k1), 0, type(uint48).max - 1));
        k2 = uint48(bound(uint256(k2), uint256(k1) + 1, type(uint48).max));

        uint208 v1 = 111;
        uint208 v2 = 222;

        harness.push(k1, v1);
        harness.push(k2, v2);

        // upperLookup at k1 returns v1 (highest checkpoint with key <= k1 is the first one).
        assertEq(harness.upperLookup(k1), v1, "upperLookup at first key must return first value");
        // upperLookup at k2 returns v2 (highest checkpoint with key <= k2 is the second one).
        assertEq(harness.upperLookup(k2), v2, "upperLookup at second key must return second value");
    }

    // -------------------------------------------------------------------------
    // Differential: linear-scan reference
    // -------------------------------------------------------------------------

    /// @notice After a fuzzed history of up to 64 pushes (repeated keys overwrite, so the trace can be shorter), the
    ///         trace's storage equals an in-memory mirror, and `upperLookup`, `upperLookupRecent` (whose sqrt pivot
    ///         runs once there are more than 5 checkpoints) and `lowerLookup` equal a linear scan of the mirror at
    ///         every stored key, its neighbours, and the clock extremes.
    function testFuzz_LookupsMatchLinearScan(uint256 seed, uint8 pushes) public {
        uint256 n = bound(pushes, 0, 64);
        uint48[] memory keys = new uint48[](n);
        uint208[] memory values = new uint208[](n);
        uint256 len;

        uint48 key = uint48(bound(seed, 0, type(uint32).max));
        for (uint256 i; i < n; ++i) {
            uint256 rand = uint256(keccak256(abi.encode(seed, i)));
            // A quarter of pushes reuse the latest key (overwrite); the rest step forward by up to 2^16.
            if (i > 0 && rand % 4 != 0) key += uint48(1 + ((rand >> 8) % (1 << 16)));
            uint208 value = uint208(rand >> 48);

            uint208 expectedPrev = len == 0 ? 0 : values[len - 1];
            (uint208 prev, uint208 next) = harness.push(key, value);
            assertEq(prev, expectedPrev, "push returns the previous latest value");
            assertEq(next, value, "push returns the new value");

            if (len > 0 && keys[len - 1] == key) {
                values[len - 1] = value;
            } else {
                keys[len] = key;
                values[len] = value;
                ++len;
            }
        }

        _assertMirror(keys, values, len);

        _assertLookups(keys, values, len, 0);
        _assertLookups(keys, values, len, type(uint48).max);
        for (uint256 i; i < len; ++i) {
            _assertLookups(keys, values, len, keys[i]);
            if (keys[i] > 0) _assertLookups(keys, values, len, keys[i] - 1);
            if (keys[i] < type(uint48).max) _assertLookups(keys, values, len, keys[i] + 1);
        }
    }

    /// @notice An out-of-order push reverts and leaves the trace unchanged.
    function testFuzz_UnorderedPushReverts(uint48 k1, uint48 k2, uint208 v) public {
        k1 = uint48(bound(k1, 1, type(uint48).max));
        k2 = uint48(bound(k2, 0, k1 - 1));
        harness.push(k1, v);

        vm.expectRevert(Checkpoints.CheckpointUnorderedInsertion.selector);
        harness.push(k2, v);
        assertEq(harness.length(), 1, "trace unchanged");
    }

    function _assertMirror(uint48[] memory keys, uint208[] memory values, uint256 len) internal view {
        assertEq(harness.length(), len, "length");
        (bool exists, uint48 lastKey, uint208 lastValue) = harness.latestCheckpoint();
        assertEq(exists, len > 0, "latestCheckpoint exists");
        assertEq(lastKey, len == 0 ? 0 : keys[len - 1], "latestCheckpoint key");
        assertEq(lastValue, len == 0 ? 0 : values[len - 1], "latestCheckpoint value");
        assertEq(harness.latest(), lastValue, "latest");
        for (uint256 i; i < len; ++i) {
            Checkpoints.Checkpoint208 memory c = harness.at(uint32(i));
            assertEq(c._key, keys[i], "at: key");
            assertEq(c._value, values[i], "at: value");
        }
    }

    function _assertLookups(uint48[] memory keys, uint208[] memory values, uint256 len, uint48 query) internal view {
        // Upper: the last checkpoint with key <= query. Lower: the first checkpoint with key >= query.
        uint208 upper;
        for (uint256 i; i < len && keys[i] <= query; ++i) {
            upper = values[i];
        }
        uint208 lower;
        for (uint256 i; i < len; ++i) {
            if (keys[i] >= query) {
                lower = values[i];
                break;
            }
        }
        assertEq(harness.upperLookup(query), upper, "upperLookup vs linear scan");
        assertEq(harness.upperLookupRecent(query), upper, "upperLookupRecent vs linear scan");
        assertEq(harness.lowerLookup(query), lower, "lowerLookup vs linear scan");
    }
}
