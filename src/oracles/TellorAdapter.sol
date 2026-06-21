// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ITellorAdapter} from "@lattice/interfaces/ITellorAdapter.sol";
import {TellorAdapterLib} from "@lattice/oracles/libraries/TellorAdapterLib.sol";

/// @title TellorAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Tellor (https://github.com/tellor-io)
/// @notice Diamond facet exposing the dispute-based Tellor oracle with per-feed dispute-buffer + staleness
///         configuration and WAD-normalized answers. Shares the {IPriceOracleReader} read surface with the
///         other Lattice oracle adapters.
/// @dev Stateless delegator — all logic and storage live in {TellorAdapterLib}. Consumers inherit this
///      contract and add AccessControl + an initializer. Reads use Tellor's `getDataBefore` at a dispute
///      buffer offset so disputed values are removed first.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Tellor
contract TellorAdapter is ITellorAdapter {
    /// @inheritdoc ITellorAdapter
    function tellor() external view virtual override returns (address) {
        return TellorAdapterLib.tellor();
    }

    /// @inheritdoc ITellorAdapter
    function getFeed(bytes32 key)
        external
        view
        virtual
        override
        returns (bytes32 queryId, uint48 disputeBuffer, uint48 maxStaleness)
    {
        return TellorAdapterLib.getFeed(key);
    }

    /// @inheritdoc ITellorAdapter
    function latestAnswer(bytes32 key) external view virtual override returns (int256 answerWad) {
        return TellorAdapterLib.latestAnswer(key);
    }

    /// @inheritdoc ITellorAdapter
    function getDataBefore(bytes32 key) external view virtual override returns (bytes memory value, uint256 timestamp) {
        return TellorAdapterLib.getDataBefore(key);
    }

    /// @inheritdoc ITellorAdapter
    function setTellor(address tellor_) external virtual override {
        TellorAdapterLib.setTellor(tellor_);
    }

    /// @inheritdoc ITellorAdapter
    function registerFeed(bytes32 key, bytes32 queryId, uint48 disputeBuffer, uint48 maxStaleness)
        external
        virtual
        override
    {
        TellorAdapterLib.registerFeed(key, queryId, disputeBuffer, maxStaleness);
    }

    /// @inheritdoc ITellorAdapter
    function unregisterFeed(bytes32 key) external virtual override {
        TellorAdapterLib.unregisterFeed(key);
    }
}
