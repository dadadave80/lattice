// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IGelatoAutomate} from "@lattice/interfaces/external/IGelatoAutomate.sol";
import {IGelatoAutomateAdapter} from "@lattice/interfaces/oracles/IGelatoAutomateAdapter.sol";
import {GelatoAutomateAdapterLib} from "@lattice/oracles/libraries/GelatoAutomateAdapterLib.sol";

/// @title GelatoAutomateAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Gelato (https://github.com/gelatodigital/automate)
/// @notice Diamond facet for Gelato Automate (Web3 Functions) task management.
/// @dev Stateless delegator — all logic and storage live in GelatoAutomateAdapterLib.
///
///      This facet handles the create/track/cancel layer only. Gelato executes a
///      created task through a task-creator-specific dedicated msg.sender; consumer
///      exec entrypoints must gate on it via the library's
///      `requireDedicatedMsgSender` guard.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Gelato
contract GelatoAutomateAdapter is IGelatoAutomateAdapter {
    /// @inheritdoc IGelatoAutomateAdapter
    function getConfig() external view virtual override returns (address automate, address dedicatedMsgSender) {
        return GelatoAutomateAdapterLib.getConfig();
    }

    /// @inheritdoc IGelatoAutomateAdapter
    function isTask(bytes32 taskId) external view virtual override returns (bool) {
        return GelatoAutomateAdapterLib.isTask(taskId);
    }

    /// @inheritdoc IGelatoAutomateAdapter
    function setConfig(address automate, address dedicatedMsgSender) external virtual override {
        GelatoAutomateAdapterLib.setConfig(automate, dedicatedMsgSender);
    }

    /// @inheritdoc IGelatoAutomateAdapter
    function createTask(
        address execAddress,
        bytes calldata execDataOrSelector,
        IGelatoAutomate.ModuleData calldata moduleData,
        address feeToken
    ) external virtual override returns (bytes32 taskId) {
        return GelatoAutomateAdapterLib.createTask(execAddress, execDataOrSelector, moduleData, feeToken);
    }

    /// @inheritdoc IGelatoAutomateAdapter
    function cancelTask(bytes32 taskId) external virtual override {
        GelatoAutomateAdapterLib.cancelTask(taskId);
    }
}
