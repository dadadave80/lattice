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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ChainlinkAutomationAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `checkUpkeep(bytes)` 0x6e04ff0d
    ///      `getCounter()` 0x8ada066e
    ///      `getForwarder()` 0xa0042526
    ///      `getInterval()` 0x91ad27b4
    ///      `getLastTimeStamp()` 0xc1c244e8
    ///      `performUpkeep(bytes)` 0x4585e33b
    ///      `setConfig(address,uint256)` 0xc6195d36
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"6e04ff0d8ada066ea004252691ad27b4c1c244e84585e33bc6195d36";
    }
}
