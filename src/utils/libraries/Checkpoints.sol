// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title Checkpoints
/// @notice Utility library for checkpointed uint208 values keyed by uint48 timepoints.
/// @dev Mirrors OpenZeppelin v5 Checkpoints (Trace208 variant).
library Checkpoints {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  ERRORS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Thrown when attempting to push a checkpoint with a key smaller than the latest key.
    error CheckpointUnorderedInsertion();

    //*//////////////////////////////////////////////////////////////////////////
    //                                  TYPES
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice A single checkpoint storing a uint208 value at a uint48 key (timepoint).
    struct Checkpoint208 {
        uint48 _key;
        uint208 _value;
    }

    /// @notice An ordered list of checkpoints.
    struct Trace208 {
        Checkpoint208[] _checkpoints;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              WRITE OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Pushes a new checkpoint. If `key` equals the latest key, replaces the value.
    ///         Reverts if `key` is less than the latest key.
    /// @param self  Storage pointer to the trace.
    /// @param key   The timepoint key (e.g. block.timestamp cast to uint48).
    /// @param value The uint208 value to store.
    /// @return The previous value at the latest checkpoint (before the update).
    /// @return The new value (same as `value`).
    function push(Trace208 storage self, uint48 key, uint208 value) internal returns (uint208, uint208) {
        uint256 len = self._checkpoints.length;
        if (len > 0) {
            Checkpoint208 storage last = self._checkpoints[len - 1];
            uint48 latestKey = last._key;
            if (key < latestKey) {
                revert CheckpointUnorderedInsertion();
            }
            uint208 prev = last._value;
            if (key == latestKey) {
                // Replace existing
                last._value = value;
                return (prev, value);
            }
            // Append new
            self._checkpoints.push(Checkpoint208({_key: key, _value: value}));
            return (prev, value);
        }
        // First checkpoint ever
        self._checkpoints.push(Checkpoint208({_key: key, _value: value}));
        return (0, value);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              READ OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the lowest value whose key is greater than or equal to `key`.
    ///         (Lower-bound lookup — useful for "find first checkpoint at or after key".)
    /// @dev Binary search. Returns 0 if all checkpoints have keys < `key`.
    function lowerLookup(Trace208 storage self, uint48 key) internal view returns (uint208) {
        uint256 len = self._checkpoints.length;
        uint256 low = 0;
        uint256 high = len;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (self._checkpoints[mid]._key < key) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        // `low` is the first index where _key >= key
        if (low == len) return 0;
        return self._checkpoints[low]._value;
    }

    /// @notice Returns the highest value whose key is less than or equal to `key`.
    ///         (Upper-bound lookup — standard "what was the value at timepoint key".)
    /// @dev Binary search. Returns 0 if all checkpoints have keys > `key`.
    function upperLookup(Trace208 storage self, uint48 key) internal view returns (uint208) {
        uint256 len = self._checkpoints.length;
        uint256 low = 0;
        uint256 high = len;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (self._checkpoints[mid]._key > key) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        // `low` is the count of checkpoints with _key <= key
        if (low == 0) return 0;
        return self._checkpoints[low - 1]._value;
    }

    /// @notice Same as `upperLookup` but starts with a linear scan from the tail.
    /// @dev Gas-optimised for recent (near-latest) timepoints: the linear phase
    ///      finds the right region fast; binary search handles older data.
    function upperLookupRecent(Trace208 storage self, uint48 key) internal view returns (uint208) {
        uint256 len = self._checkpoints.length;
        if (len == 0) return 0;

        // Linear scan from the end — stops when we pass the target key
        uint256 low = 0;
        uint256 high = len;

        if (len > 5) {
            // Start linear scan from the tail
            uint256 window = 5;
            while (window < len) {
                uint256 idx = len - window;
                if (self._checkpoints[idx]._key <= key) {
                    low = idx;
                    break;
                }
                // if the checkpoint at idx is still > key, shrink search space
                high = idx;
                window *= 2;
            }
        }

        // Binary search within [low, high)
        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (self._checkpoints[mid]._key > key) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        if (low == 0) return 0;
        return self._checkpoints[low - 1]._value;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            CONVENIENCE VIEWS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the value of the most recently pushed checkpoint, or 0 if empty.
    function latest(Trace208 storage self) internal view returns (uint208) {
        uint256 len = self._checkpoints.length;
        if (len == 0) return 0;
        return self._checkpoints[len - 1]._value;
    }

    /// @notice Returns whether there is at least one checkpoint, and if so, its key and value.
    function latestCheckpoint(Trace208 storage self) internal view returns (bool exists, uint48 _key, uint208 _value) {
        uint256 len = self._checkpoints.length;
        if (len == 0) return (false, 0, 0);
        Checkpoint208 storage last = self._checkpoints[len - 1];
        return (true, last._key, last._value);
    }

    /// @notice Returns the total number of checkpoints stored.
    function length(Trace208 storage self) internal view returns (uint256) {
        return self._checkpoints.length;
    }

    /// @notice Returns the checkpoint at the given position (0-indexed).
    function at(Trace208 storage self, uint32 pos) internal view returns (Checkpoint208 memory) {
        return self._checkpoints[pos];
    }
}
