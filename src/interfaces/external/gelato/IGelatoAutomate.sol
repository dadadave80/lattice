// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IGelatoAutomate
/// @author Modified from Gelato (https://github.com/gelatodigital/automate/blob/master/contracts/interfaces/IAutomate.sol)
/// @notice Minimal interface for the Gelato Automate (Web3 Functions / keeper) task manager.
/// @dev Vendored subset — do not add a gelato dependency. Gelato executes a created task through a
///      task-creator-specific **dedicated msg.sender** (the Automate proxy); every exec entrypoint
///      must gate on it.
interface IGelatoAutomate {
    /// @notice Task module kinds, combined via `ModuleData` when creating a task.
    enum Module {
        RESOLVER,
        DEADLINE,
        PROXY,
        SINGLE_EXEC,
        WEB3_FUNCTION,
        TRIGGER
    }

    /// @notice The set of modules (and their ABI-encoded args) attached to a task.
    struct ModuleData {
        Module[] modules;
        bytes[] args;
    }

    /// @notice Creates an automation task.
    /// @param execAddress        The contract Gelato will call when the task runs.
    /// @param execDataOrSelector The calldata (or selector, for resolver/web3-function modules) to run.
    /// @param moduleData         The modules configuring how/when the task triggers.
    /// @param feeToken           The fee token (address(0) for native; off-chain via 1Balance otherwise).
    /// @return taskId The identifier assigned to the created task.
    function createTask(
        address execAddress,
        bytes calldata execDataOrSelector,
        ModuleData calldata moduleData,
        address feeToken
    ) external returns (bytes32 taskId);

    /// @notice Cancels a previously created task.
    /// @param taskId The task to cancel.
    function cancelTask(bytes32 taskId) external;
}
