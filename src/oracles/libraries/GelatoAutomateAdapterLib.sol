// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IGelatoAutomateAdapter} from "@lattice/interfaces/IGelatoAutomateAdapter.sol";
import {IGelatoAutomate} from "@lattice/interfaces/external/IGelatoAutomate.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.GelatoAutomateAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant GELATO_AUTOMATE_ADAPTER_STORAGE_SLOT =
    0x2e009cfe8b023d727b88173e4903cf45c68c8d769ec207081d89791b624d6900;

/// @dev 0xa5503dc2 is `type(IGelatoAutomateAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xa5503dc2), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IGELATOAUTOMATEADAPTER_SLOT =
    0x266c2a44ce0cae7d2ae6065711c72b357de4f867c756d7ce5224cd89d213768f;

/// @notice ERC-7201 namespaced storage for GelatoAutomateAdapter.
/// @custom:storage-location erc7201:lattice.storage.GelatoAutomateAdapter
struct GelatoAutomateAdapterStorage {
    address _automate;
    address _dedicatedMsgSender;
    mapping(bytes32 taskId => bool tracked) _tasks;
}

/// @title GelatoAutomateAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Gelato (https://github.com/gelatodigital/automate)
/// @notice Library that wraps Gelato Automate (Web3 Functions) task management.
///         This is the create/track/cancel layer; Gelato executes a created task
///         through a task-creator-specific dedicated msg.sender. Consumer exec
///         entrypoints must gate on it via `requireDedicatedMsgSender`.
library GelatoAutomateAdapterLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the ERC-7201 storage struct for GelatoAutomateAdapter.
    function gelatoAutomateAdapterStorage() internal pure returns (GelatoAutomateAdapterStorage storage $) {
        assembly {
            $.slot := GELATO_AUTOMATE_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IGelatoAutomateAdapter ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __GelatoAutomateAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for IGelatoAutomateAdapter.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IGELATOAUTOMATEADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the current Automate configuration.
    /// @return automate           The Gelato Automate contract.
    /// @return dedicatedMsgSender The dedicated msg.sender Gelato execs through.
    function getConfig() internal view returns (address automate, address dedicatedMsgSender) {
        GelatoAutomateAdapterStorage storage $ = gelatoAutomateAdapterStorage();
        automate = $._automate;
        dedicatedMsgSender = $._dedicatedMsgSender;
    }

    /// @notice Returns whether `taskId` is tracked by this adapter.
    /// @param taskId The task ID to query.
    function isTask(bytes32 taskId) internal view returns (bool) {
        return gelatoAutomateAdapterStorage()._tasks[taskId];
    }

    /// @notice Reverts unless both the Automate contract and dedicated msg.sender are set.
    /// @dev Reverts `GelatoAutomateNotConfigured` if either field is zero.
    /// @return a The configured Gelato Automate contract.
    function _requireConfigured() internal view returns (address a) {
        GelatoAutomateAdapterStorage storage $ = gelatoAutomateAdapterStorage();
        a = $._automate;
        if (a == address(0) || $._dedicatedMsgSender == address(0)) {
            revert IGelatoAutomateAdapter.GelatoAutomateNotConfigured();
        }
    }

    /// @notice Enforces the dedicated msg.sender on consumer exec entrypoints.
    /// @dev Consumer exec entrypoints call this. It is the dedicatedMsgSender
    ///      enforcement on the exec path: Gelato runs a created task through a
    ///      task-creator-specific dedicated msg.sender, and only that address may
    ///      drive the exec flow. Reverts `GelatoAutomateOnlyDedicatedMsgSender`.
    function requireDedicatedMsgSender() internal view {
        GelatoAutomateAdapterStorage storage $ = gelatoAutomateAdapterStorage();
        if (msg.sender != $._dedicatedMsgSender) {
            revert IGelatoAutomateAdapter.GelatoAutomateOnlyDedicatedMsgSender(msg.sender);
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets or replaces the Automate configuration.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    ///      Reverts `GelatoAutomateInvalidConfig` if either address is zero.
    /// @param automate           The Gelato Automate contract.
    /// @param dedicatedMsgSender The dedicated msg.sender Gelato execs through.
    function setConfig(address automate, address dedicatedMsgSender) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (automate == address(0) || dedicatedMsgSender == address(0)) {
            revert IGelatoAutomateAdapter.GelatoAutomateInvalidConfig();
        }
        GelatoAutomateAdapterStorage storage $ = gelatoAutomateAdapterStorage();
        $._automate = automate;
        $._dedicatedMsgSender = dedicatedMsgSender;
        emit IGelatoAutomateAdapter.GelatoAutomateConfigSet(automate, dedicatedMsgSender);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Creates and tracks a Gelato Automate task.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    ///      Reverts `GelatoAutomateNotConfigured` if not configured.
    ///      Reverts `GelatoAutomateTaskExists` if the returned task ID is already tracked.
    /// @param execAddress        The contract Gelato will call when the task runs.
    /// @param execDataOrSelector The calldata (or selector) to run.
    /// @param moduleData         The modules configuring how/when the task triggers.
    /// @param feeToken           The fee token (address(0) for native).
    /// @return taskId The Automate-assigned task ID.
    function createTask(
        address execAddress,
        bytes calldata execDataOrSelector,
        IGelatoAutomate.ModuleData calldata moduleData,
        address feeToken
    ) internal returns (bytes32 taskId) {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        address a = _requireConfigured();
        taskId = IGelatoAutomate(a).createTask(execAddress, execDataOrSelector, moduleData, feeToken);
        GelatoAutomateAdapterStorage storage $ = gelatoAutomateAdapterStorage();
        if ($._tasks[taskId]) revert IGelatoAutomateAdapter.GelatoAutomateTaskExists(taskId);
        $._tasks[taskId] = true;
        emit IGelatoAutomateAdapter.TaskCreated(taskId, execAddress);
    }

    /// @notice Cancels and untracks a Gelato Automate task.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    ///      Reverts `GelatoAutomateNotConfigured` if not configured.
    ///      Reverts `GelatoAutomateTaskNotFound` if the task is not tracked.
    /// @param taskId The task to cancel.
    function cancelTask(bytes32 taskId) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        address a = _requireConfigured();
        GelatoAutomateAdapterStorage storage $ = gelatoAutomateAdapterStorage();
        if (!$._tasks[taskId]) revert IGelatoAutomateAdapter.GelatoAutomateTaskNotFound(taskId);
        delete $._tasks[taskId];
        IGelatoAutomate(a).cancelTask(taskId);
        emit IGelatoAutomateAdapter.TaskCancelled(taskId);
    }
}
