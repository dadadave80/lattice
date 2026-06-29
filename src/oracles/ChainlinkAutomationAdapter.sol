// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IChainlinkAutomationAdapter} from "@lattice/interfaces/oracles/IChainlinkAutomationAdapter.sol";
import {ChainlinkAutomationAdapterLib} from "@lattice/oracles/libraries/ChainlinkAutomationAdapterLib.sol";

/// @title ChainlinkAutomationAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Chainlink (https://github.com/smartcontractkit/chainlink-evm)
/// @notice Diamond facet for the consumer side of Chainlink Automation (keepers)
///         with a canonical time-interval upkeep.
/// @dev Stateless delegator — all logic and storage live in
///      ChainlinkAutomationAdapterLib.
///
///      DECISION (recorded): this ships the consumer-side compatible facet only.
///      The optional AutomationRegistrar/AutomationRegistry on-chain
///      registration + LINK-funding surface is a separate concern and
///      intentionally left as a future follow-up — no registrar/registry
///      management is performed here.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Chainlink
contract ChainlinkAutomationAdapter is IChainlinkAutomationAdapter {
    /// @inheritdoc IChainlinkAutomationAdapter
    function getForwarder() external view virtual override returns (address) {
        return ChainlinkAutomationAdapterLib.getForwarder();
    }

    /// @inheritdoc IChainlinkAutomationAdapter
    function getInterval() external view virtual override returns (uint256) {
        return ChainlinkAutomationAdapterLib.getInterval();
    }

    /// @inheritdoc IChainlinkAutomationAdapter
    function getLastTimeStamp() external view virtual override returns (uint256) {
        return ChainlinkAutomationAdapterLib.getLastTimeStamp();
    }

    /// @inheritdoc IChainlinkAutomationAdapter
    function getCounter() external view virtual override returns (uint256) {
        return ChainlinkAutomationAdapterLib.getCounter();
    }

    /// @inheritdoc IChainlinkAutomationAdapter
    function checkUpkeep(bytes calldata checkData)
        external
        view
        virtual
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        return ChainlinkAutomationAdapterLib.checkUpkeep(checkData);
    }

    /// @inheritdoc IChainlinkAutomationAdapter
    function setConfig(address forwarder, uint256 interval) external virtual override {
        ChainlinkAutomationAdapterLib.setConfig(forwarder, interval);
    }

    /// @inheritdoc IChainlinkAutomationAdapter
    function performUpkeep(bytes calldata performData) external virtual override {
        ChainlinkAutomationAdapterLib.performUpkeep(performData);
    }
}
