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

    function latest() external view returns (uint208) {
        return Checkpoints.latest(_trace);
    }

    function length() external view returns (uint256) {
        return Checkpoints.length(_trace);
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
}
