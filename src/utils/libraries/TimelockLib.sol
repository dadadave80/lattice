// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title TimelockLib
/// @notice Scheduling primitives for time-locked operations. Two storage shapes:
///         - `SingleSchedule`: at most one pending operation of this kind
///         - `MultiSchedule`:  many concurrent pending operations keyed by bytes32
/// @dev Stateless utility library — no own ERC-7201 slot. The consumer holds
///      `SingleSchedule` / `MultiSchedule` instances inside its own storage.
library TimelockLib {
    struct SingleSchedule {
        uint48 _readyAt;
    }

    struct MultiSchedule {
        mapping(bytes32 operationId => uint48 readyAt) _readyAt;
    }

    /// @dev The schedule is empty (no operation pending).
    error TimelockNotPending();

    /// @dev `now` < `readyAt`; the operation cannot be consumed yet.
    error TimelockNotReady(uint48 readyAt, uint48 nowTs);

    /// @dev The schedule already has a pending operation that hasn't been consumed/canceled.
    error TimelockAlreadyPending(uint48 readyAt);

    // ---- SingleSchedule operations ----

    function schedule(SingleSchedule storage s, uint48 delay) internal returns (uint48 readyAt) {
        if (s._readyAt != 0) revert TimelockAlreadyPending(s._readyAt);
        readyAt = uint48(block.timestamp) + delay;
        s._readyAt = readyAt;
    }

    function reschedule(SingleSchedule storage s, uint48 newReadyAt) internal {
        if (s._readyAt == 0) revert TimelockNotPending();
        s._readyAt = newReadyAt;
    }

    function consume(SingleSchedule storage s) internal {
        uint48 ready = s._readyAt;
        if (ready == 0) revert TimelockNotPending();
        if (block.timestamp < ready) revert TimelockNotReady(ready, uint48(block.timestamp));
        s._readyAt = 0;
    }

    function cancel(SingleSchedule storage s) internal {
        if (s._readyAt == 0) revert TimelockNotPending();
        s._readyAt = 0;
    }

    function readyAt(SingleSchedule storage s) internal view returns (uint48) {
        return s._readyAt;
    }

    function isPending(SingleSchedule storage s) internal view returns (bool) {
        return s._readyAt != 0;
    }

    function isReady(SingleSchedule storage s) internal view returns (bool) {
        uint48 r = s._readyAt;
        return r != 0 && block.timestamp >= r;
    }

    // ---- MultiSchedule operations ----

    function schedule(MultiSchedule storage s, bytes32 operationId, uint48 delay) internal returns (uint48 readyAt_) {
        uint48 current = s._readyAt[operationId];
        if (current != 0) revert TimelockAlreadyPending(current);
        readyAt_ = uint48(block.timestamp) + delay;
        s._readyAt[operationId] = readyAt_;
    }

    function reschedule(MultiSchedule storage s, bytes32 operationId, uint48 newReadyAt) internal {
        if (s._readyAt[operationId] == 0) revert TimelockNotPending();
        s._readyAt[operationId] = newReadyAt;
    }

    function consume(MultiSchedule storage s, bytes32 operationId) internal {
        uint48 ready = s._readyAt[operationId];
        if (ready == 0) revert TimelockNotPending();
        if (block.timestamp < ready) revert TimelockNotReady(ready, uint48(block.timestamp));
        s._readyAt[operationId] = 0;
    }

    function cancel(MultiSchedule storage s, bytes32 operationId) internal {
        if (s._readyAt[operationId] == 0) revert TimelockNotPending();
        s._readyAt[operationId] = 0;
    }

    function readyAt(MultiSchedule storage s, bytes32 operationId) internal view returns (uint48) {
        return s._readyAt[operationId];
    }

    function isPending(MultiSchedule storage s, bytes32 operationId) internal view returns (bool) {
        return s._readyAt[operationId] != 0;
    }

    function isReady(MultiSchedule storage s, bytes32 operationId) internal view returns (bool) {
        uint48 r = s._readyAt[operationId];
        return r != 0 && block.timestamp >= r;
    }
}
