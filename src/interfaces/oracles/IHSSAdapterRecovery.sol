// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IHSSAdapterRecovery
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from hiero-ledger/hiero-contracts (https://github.com/hiero-ledger/hiero-contracts)
/// @notice Generation-bound callback dispatch and local recovery for HSSAdapter jobs.
/// @dev Separate from the live IHSSAdapter interface; its original selector set and id remain frozen.
interface IHSSAdapterRecovery {
    event HSSSelfCallGeneration(bytes32 indexed jobId, uint256 indexed generation, address indexed scheduleAddress);
    event HSSSelfCallCancelled(
        bytes32 indexed jobId, address indexed scheduleAddress, uint256 generation, bool scheduleDeleted
    );

    error HSSNoScheduledJob(bytes32 jobId);
    error HSSStaleSelfCall(bytes32 jobId, uint256 generation);
    error HSSInvalidExecutionContext(bytes32 jobId);
    error HSSSelfCallAlreadyExecuting();
    error HSSRecoveryNotInstalled();

    /// @notice Invalidates a job locally and attempts native deletion. Requires HSS_SCHEDULER_ROLE.
    /// @dev Local cancellation succeeds independently of native deletion's response. Wrapped stale callbacks
    ///      are rejected before their payload executes. Legacy unwrapped payloads may still run if native
    ///      deletion fails, but cannot complete a generation-bound job. Native deletion has a 100,000 gas cap;
    ///      low-gas calls reserve event/return gas and can skip that attempt. Monitor the returned flag/event.
    function cancelSelfCall(bytes32 jobId) external returns (bool scheduleDeleted);

    /// @notice Native self-call envelope; accepts only the diamond and the currently booked generation.
    /// @dev The original callback executes with the diamond as caller and must explicitly complete its job.
    ///      Self-call authority is a composition trust boundary, not proof of native HSS origin. Do not install
    ///      unrestricted self-call executors. The native payer-as-sender assumption still needs live proof.
    function executeSelfCall(bytes32 jobId, uint256 generation, bytes calldata data) external;
}
