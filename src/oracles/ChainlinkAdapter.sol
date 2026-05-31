// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IChainlinkAdapter} from "@lattice/interfaces/IChainlinkAdapter.sol";
import {ChainlinkAdapterLib} from "@lattice/oracles/libraries/ChainlinkAdapterLib.sol";

/// @title ChainlinkAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Chainlink (https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol)
/// @notice Diamond facet that exposes Chainlink AggregatorV3 price feeds with
///         per-feed staleness configuration and WAD-normalised answers.
/// @dev Stateless delegator — all logic and storage live in ChainlinkAdapterLib.
///      Consumers inherit this contract and add AccessControl + an initializer.
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
}
