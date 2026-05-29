// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ITimelockController
/// @notice Interface for the TimelockController module, which schedules and executes
///         governance actions after a minimum delay.
/// @dev Mirrors the OpenZeppelin v5 TimelockController interface.
interface ITimelockController {
    /// @notice The state of a scheduled operation.
    /// @dev Unset=0 (never scheduled), Waiting=1 (scheduled but not yet ready),
    ///      Ready=2 (past the delay, not yet executed), Done=3 (executed).
    enum OperationState {
        Unset,
        Waiting,
        Ready,
        Done
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   EVENTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Emitted when a call is scheduled as part of an operation.
    /// @param id The unique operation id.
    /// @param index The index of the call within a batch (0 for single calls).
    /// @param target The target contract address.
    /// @param value The ETH value sent with the call.
    /// @param data The call data.
    /// @param predecessor The predecessor operation id (0 for no predecessor).
    /// @param delay The delay before the call can be executed.
    event CallScheduled(
        bytes32 indexed id,
        uint256 indexed index,
        address target,
        uint256 value,
        bytes data,
        bytes32 predecessor,
        uint256 delay
    );

    /// @dev Emitted when a call is executed as part of an operation.
    /// @param id The unique operation id.
    /// @param index The index of the call within a batch (0 for single calls).
    /// @param target The target contract address.
    /// @param value The ETH value sent with the call.
    /// @param data The call data.
    event CallExecuted(bytes32 indexed id, uint256 indexed index, address target, uint256 value, bytes data);

    /// @dev Emitted when a salt is used in an operation, providing extra entropy.
    /// @param id The unique operation id.
    /// @param salt The salt value used.
    event CallSalt(bytes32 indexed id, bytes32 salt);

    /// @dev Emitted when an operation is cancelled.
    /// @param id The unique operation id.
    event Cancelled(bytes32 indexed id);

    /// @dev Emitted when the minimum delay for future operations is modified.
    /// @param oldDuration The previous minimum delay.
    /// @param newDuration The new minimum delay.
    event MinDelayChange(uint256 oldDuration, uint256 newDuration);

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ERRORS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Thrown when the number of targets, payloads, and values do not match in a batch.
    /// @param targets The number of target addresses provided.
    /// @param payloads The number of payloads provided.
    /// @param values The number of values provided.
    error TimelockInvalidOperationLength(uint256 targets, uint256 payloads, uint256 values);

    /// @dev Thrown when the proposed delay is less than the current minimum delay.
    /// @param delay The proposed delay.
    /// @param minDelay The current minimum delay.
    error TimelockInsufficientDelay(uint256 delay, uint256 minDelay);

    /// @dev Thrown when an operation is not in the expected state.
    /// @param operationId The operation id.
    /// @param expectedStates A bitmap of acceptable OperationState values.
    error TimelockUnexpectedOperationState(bytes32 operationId, bytes32 expectedStates);

    /// @dev Thrown when a predecessor operation has not been executed yet.
    /// @param predecessorId The predecessor operation id.
    error TimelockUnexecutedPredecessor(bytes32 predecessorId);

    /// @dev Thrown when the caller is not authorized to perform the requested action.
    /// @param caller The caller address.
    error TimelockUnauthorizedCaller(address caller);

    //*//////////////////////////////////////////////////////////////////////////
    //                              ROLE CONSTANTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The role identifier for proposers (and cancellers) — `keccak256("PROPOSER_ROLE")`.
    function PROPOSER_ROLE() external pure returns (bytes32);

    /// @notice The role identifier for executors — `keccak256("EXECUTOR_ROLE")`.
    function EXECUTOR_ROLE() external pure returns (bytes32);

    /// @notice The role identifier for cancellers — `keccak256("CANCELLER_ROLE")`.
    function CANCELLER_ROLE() external pure returns (bytes32);

    //*//////////////////////////////////////////////////////////////////////////
    //                                 VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns whether an id corresponds to a registered operation.
    function isOperation(bytes32 id) external view returns (bool);

    /// @notice Returns whether an operation is pending (Waiting or Ready).
    function isOperationPending(bytes32 id) external view returns (bool);

    /// @notice Returns whether an operation is ready for execution.
    function isOperationReady(bytes32 id) external view returns (bool);

    /// @notice Returns whether an operation has been executed.
    function isOperationDone(bytes32 id) external view returns (bool);

    /// @notice Returns the state of an operation.
    function getOperationState(bytes32 id) external view returns (OperationState);

    /// @notice Returns the timestamp at which an operation becomes ready.
    /// @dev Returns 0 for Unset, 1 (DONE_TIMESTAMP) for Done, and the scheduled timestamp otherwise.
    function getTimestamp(bytes32 id) external view returns (uint256);

    /// @notice Returns the minimum delay required before an operation can be executed.
    function getMinDelay() external view returns (uint256);

    /// @notice Returns the identifier of an operation containing a single transaction.
    function hashOperation(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt)
        external
        pure
        returns (bytes32);

    /// @notice Returns the identifier of an operation containing a batch of transactions.
    function hashOperationBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) external pure returns (bytes32);

    //*//////////////////////////////////////////////////////////////////////////
    //                              MUTATING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Schedule an operation containing a single transaction.
    /// @param target The target contract.
    /// @param value The ETH value.
    /// @param data The call data.
    /// @param predecessor An optional preceding operation that must be done first.
    /// @param salt An optional salt for uniqueness.
    /// @param delay The delay before execution is allowed (must be >= minDelay).
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external;

    /// @notice Schedule an operation containing a batch of transactions.
    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external;

    /// @notice Cancel an operation.
    /// @param id The operation id.
    function cancel(bytes32 id) external;

    /// @notice Execute a (ready) operation containing a single transaction.
    function execute(address target, uint256 value, bytes calldata payload, bytes32 predecessor, bytes32 salt)
        external
        payable;

    /// @notice Execute a (ready) operation containing a batch of transactions.
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) external payable;

    /// @notice Changes the minimum timelock duration for future operations.
    /// @dev Must be called by the timelock itself (via a scheduled + executed operation).
    /// @param newDelay The new minimum delay.
    function updateDelay(uint256 newDelay) external;
}
