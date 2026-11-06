// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IHSSAdapter
/// @author Modified from hiero-ledger/hiero-contracts (https://github.com/hiero-ledger/hiero-contracts)
/// @notice Interface for the HSSAdapter Diamond facet — Hedera Schedule Service (HIP-755 contract signatures on
///         native scheduled transactions, HIP-1215 scheduled contract calls) as the diamond's native
///         automation: the diamond schedules a call (typically to itself) that the network executes at
///         `expirySecond`, paid from the diamond's own HBAR. The payer-as-callback-sender assumption remains unverified on-chain.
/// @dev Sits beside the Chainlink / Gelato automation adapters. A scheduled call is a one-shot; recurring jobs
///      re-schedule themselves from inside the callback. Capacity per consensus second is throttled — check
///      {hasScheduleCapacity} first; `expirySecond` must be later than now and at most ~62 days ahead.
interface IHSSAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a contract call is scheduled. `jobId` is zero for calls scheduled by {scheduleCall}.
    event HSSCallScheduled(
        address indexed scheduleAddress,
        address indexed target,
        bytes32 indexed jobId,
        uint256 expirySecond,
        uint256 gasLimit
    );

    /// @notice Emitted when a schedule is deleted by the diamond (it holds the schedule's admin key).
    event HSSScheduleDeleted(address indexed scheduleAddress);

    /// @notice Emitted when the diamond signs a native scheduled transaction with its contract key.
    event HSSScheduleAuthorized(address indexed scheduleAddress);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice HSS function `selector` returned `responseCode`.
    error HSSCallFailed(bytes4 selector, int64 responseCode);
    /// @notice The network has no scheduling capacity for `gasLimit` at `expirySecond` (HSS 370).
    error HSSExpiryBusy(uint256 expirySecond, uint256 gasLimit);
    /// @notice `expirySecond` is not in the future.
    error HSSInvalidExpiry(uint256 expirySecond);
    /// @notice The caller is not the diamond executing one of its own scheduled calls.
    error HSSNotScheduledSelfCall();
    /// @notice `jobId` already has a live schedule.
    error HSSJobAlreadyScheduled(bytes32 jobId, address scheduleAddress);

    // -------------------------------------------------------------------------
    //                                   Reads
    // -------------------------------------------------------------------------

    /// @notice True if the network can still accept a `gasLimit` call at `expirySecond`.
    function hasScheduleCapacity(uint256 expirySecond, uint256 gasLimit) external view returns (bool);

    /// @notice The schedule address recorded for `jobId` (zero if none / already cleared).
    function scheduleOf(bytes32 jobId) external view returns (address scheduleAddress);

    // -------------------------------------------------------------------------
    //                        Scheduling (HSS_SCHEDULER_ROLE)
    // -------------------------------------------------------------------------

    /// @notice Schedules `to.call{value}(data)` at `expirySecond`, paid by the diamond, executed with the
    ///         expected diamond-as-sender semantics still pending native verification. Returns its schedule address.
    function scheduleCall(address to, uint256 expirySecond, uint256 gasLimit, uint64 value, bytes calldata data)
        external
        returns (address scheduleAddress);

    /// @notice Schedules a call to the diamond itself under `jobId` (one live schedule per job). The callback
    ///         must clear the job via {completeSelfCall} so it can be re-scheduled.
    /// @dev The matching HSSAdapterRecovery facet must be installed. New bookings wrap `data` in a
    ///      generation-bound envelope, which authenticates the self caller before executing the payload.
    ///      A scheduler-role holder may cancel a stranded job through IHSSAdapterRecovery. The frozen
    ///      interfaceId and selectors of this interface are unchanged. After an upgrade, cancel and replace
    ///      legacy raw jobs: they cannot complete a generation-bound job, but their raw payload may still
    ///      execute if native deletion fails. Native callback sender identity still requires probe6 evidence.
    function scheduleSelfCall(bytes32 jobId, uint256 expirySecond, uint256 gasLimit, bytes calldata data)
        external
        returns (address scheduleAddress);

    /// @notice Deletes a schedule the diamond created (HIP-1215 `deleteSchedule`).
    function deleteSchedule(address scheduleAddress) external;

    /// @notice Signs a native scheduled transaction with the diamond's contract key (HIP-755).
    function authorizeSchedule(address scheduleAddress) external;

    // -------------------------------------------------------------------------
    //                        Callback plumbing (self only)
    // -------------------------------------------------------------------------

    /// @notice Clears `jobId` only inside its matching generation envelope, with the diamond as caller.
    function completeSelfCall(bytes32 jobId) external;
}
