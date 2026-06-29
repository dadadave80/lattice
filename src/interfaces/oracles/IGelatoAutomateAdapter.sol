// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IGelatoAutomate} from "@lattice/interfaces/external/IGelatoAutomate.sol";

/// @title IGelatoAutomateAdapter
/// @notice Interface for the GelatoAutomateAdapter Diamond facet — Gelato Automate (Web3 Functions)
///         task management. Establishes the automation/keeper family.
/// @dev Lets a Diamond create, track, and cancel Gelato Automate tasks. Gelato executes a task through
///      a task-creator-specific **dedicated msg.sender**; consumer exec entrypoints must gate on it via
///      the library's `requireDedicatedMsgSender` guard. Task creation/cancellation are admin-gated.
interface IGelatoAutomateAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when the Automate configuration is updated.
    /// @param automate           The Gelato Automate contract.
    /// @param dedicatedMsgSender The dedicated msg.sender Gelato execs through.
    event GelatoAutomateConfigSet(address automate, address dedicatedMsgSender);

    /// @notice Emitted when a task is created.
    /// @param taskId      The Automate-assigned task ID.
    /// @param execAddress The contract Gelato will call when the task runs.
    event TaskCreated(bytes32 indexed taskId, address execAddress);

    /// @notice Emitted when a task is cancelled.
    /// @param taskId The cancelled task ID.
    event TaskCancelled(bytes32 indexed taskId);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice Automate has not been configured (automate or dedicatedMsgSender is zero).
    error GelatoAutomateNotConfigured();

    /// @notice `setConfig` was called with a zero automate or dedicatedMsgSender address.
    error GelatoAutomateInvalidConfig();

    /// @notice An exec entrypoint was called by an address other than the dedicated msg.sender.
    /// @param caller The unauthorised caller.
    error GelatoAutomateOnlyDedicatedMsgSender(address caller);

    /// @notice The given task ID is not tracked by this adapter.
    /// @param taskId The unknown task ID.
    error GelatoAutomateTaskNotFound(bytes32 taskId);

    /// @notice A task with the given ID is already tracked.
    /// @param taskId The duplicate task ID.
    error GelatoAutomateTaskExists(bytes32 taskId);

    // -------------------------------------------------------------------------
    //                                   Reads
    // -------------------------------------------------------------------------

    /// @notice Returns the current Automate configuration.
    /// @return automate           The Gelato Automate contract.
    /// @return dedicatedMsgSender The dedicated msg.sender Gelato execs through.
    function getConfig() external view returns (address automate, address dedicatedMsgSender);

    /// @notice Returns whether `taskId` is tracked by this adapter.
    /// @param taskId The task ID to query.
    function isTask(bytes32 taskId) external view returns (bool);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Sets or replaces the Automate configuration.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`. Reverts `GelatoAutomateInvalidConfig` on a zero field.
    /// @param automate           The Gelato Automate contract.
    /// @param dedicatedMsgSender The dedicated msg.sender Gelato execs through (derived off-chain via
    ///                           the OpsProxyFactory for this diamond).
    function setConfig(address automate, address dedicatedMsgSender) external;

    /// @notice Creates and tracks a Gelato Automate task.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param execAddress        The contract Gelato will call when the task runs.
    /// @param execDataOrSelector The calldata (or selector) to run.
    /// @param moduleData         The modules configuring how/when the task triggers.
    /// @param feeToken           The fee token (address(0) for native; off-chain via 1Balance otherwise).
    /// @return taskId The Automate-assigned task ID.
    function createTask(
        address execAddress,
        bytes calldata execDataOrSelector,
        IGelatoAutomate.ModuleData calldata moduleData,
        address feeToken
    ) external returns (bytes32 taskId);

    /// @notice Cancels and untracks a Gelato Automate task.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`. Reverts `GelatoAutomateTaskNotFound` if untracked.
    /// @param taskId The task to cancel.
    function cancelTask(bytes32 taskId) external;
}
