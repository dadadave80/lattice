// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IChainlinkAdapter} from "@lattice/interfaces/oracles/IChainlinkAdapter.sol";
import {ChainlinkAdapterLib} from "@lattice/oracles/chainlink/ChainlinkAdapterLib.sol";

/// @title ChainlinkAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Chainlink (https://github.com/smartcontractkit/chainlink-evm/blob/develop/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol)
/// @notice Diamond facet that exposes Chainlink AggregatorV3 price feeds with
///         per-feed staleness configuration and WAD-normalised answers.
/// @dev Stateless delegator — all logic and storage live in ChainlinkAdapterLib.
///      Consumers inherit this contract and add AccessControl + an initializer.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Chainlink
contract ChainlinkAdapter is IChainlinkAdapter {
    /// @inheritdoc IChainlinkAdapter
    function getFeed(bytes32 key) external view virtual override returns (address feed, uint48 maxStaleness) {
        return ChainlinkAdapterLib.getFeed(key);
    }

    /// @inheritdoc IChainlinkAdapter
    function latestAnswer(bytes32 key) external view virtual override returns (int256 answerWad) {
        return ChainlinkAdapterLib.latestAnswer(key);
    }

    /// @inheritdoc IChainlinkAdapter
    function latestAnswerRaw(bytes32 key)
        external
        view
        virtual
        override
        returns (int256 answer, uint256 updatedAt, uint8 decimals_)
    {
        return ChainlinkAdapterLib.latestAnswerRaw(key);
    }

    /// @inheritdoc IChainlinkAdapter
    function registerFeed(bytes32 key, address feed, uint48 maxStaleness) external virtual override {
        ChainlinkAdapterLib.registerFeed(key, feed, maxStaleness);
    }

    /// @inheritdoc IChainlinkAdapter
    function unregisterFeed(bytes32 key) external virtual override {
        ChainlinkAdapterLib.unregisterFeed(key);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ChainlinkAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `getFeed(bytes32)` 0x280aebcf
    ///      `latestAnswer(bytes32)` 0x084d4783
    ///      `latestAnswerRaw(bytes32)` 0xad0ddbee
    ///      `registerFeed(bytes32,address,uint48)` 0x915d3063
    ///      `unregisterFeed(bytes32)` 0x2a589908
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"280aebcf084d4783ad0ddbee915d30632a589908";
    }
}
