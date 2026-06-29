// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IRedStoneAdapter} from "@lattice/interfaces/oracles/IRedStoneAdapter.sol";
import {RedStoneAdapterLib} from "@lattice/oracles/libraries/RedStoneAdapterLib.sol";

/// @title RedStoneAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from RedStone (https://github.com/redstone-finance/redstone-oracles-monorepo)
/// @notice Diamond facet that reads RedStone Push price feeds from their on-chain PriceFeedsAdapter with
///         per-feed staleness configuration and WAD-normalized answers.
/// @dev Stateless delegator — all logic and storage live in {RedStoneAdapterLib}. Consumers inherit this
///      contract and add AccessControl + an initializer.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source RedStone
contract RedStoneAdapter is IRedStoneAdapter {
    /// @inheritdoc IRedStoneAdapter
    function getFeed(bytes32 key)
        external
        view
        virtual
        override
        returns (address adapter, bytes32 dataFeedId, uint48 maxStaleness)
    {
        return RedStoneAdapterLib.getFeed(key);
    }

    /// @inheritdoc IRedStoneAdapter
    function latestAnswer(bytes32 key) external view virtual override returns (int256 answerWad) {
        return RedStoneAdapterLib.latestAnswer(key);
    }

    /// @inheritdoc IRedStoneAdapter
    function getValueForDataFeed(bytes32 key)
        external
        view
        virtual
        override
        returns (uint256 value, uint256 timestamp)
    {
        return RedStoneAdapterLib.getValueForDataFeed(key);
    }

    /// @inheritdoc IRedStoneAdapter
    function registerFeed(bytes32 key, address adapter, bytes32 dataFeedId, uint48 maxStaleness)
        external
        virtual
        override
    {
        RedStoneAdapterLib.registerFeed(key, adapter, dataFeedId, maxStaleness);
    }

    /// @inheritdoc IRedStoneAdapter
    function unregisterFeed(bytes32 key) external virtual override {
        RedStoneAdapterLib.unregisterFeed(key);
    }
}
