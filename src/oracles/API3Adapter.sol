// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAPI3Adapter} from "@lattice/interfaces/IAPI3Adapter.sol";
import {API3AdapterLib} from "@lattice/oracles/libraries/API3AdapterLib.sol";

/// @title API3Adapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from API3 (https://github.com/api3dao/contracts)
/// @notice Diamond facet that reads API3 dAPIs through their reader proxies with per-feed staleness
///         configuration and WAD-normalized answers.
/// @dev Stateless delegator — all logic and storage live in {API3AdapterLib}. Consumers inherit this
///      contract and add AccessControl + an initializer.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source API3
contract API3Adapter is IAPI3Adapter {
    /// @inheritdoc IAPI3Adapter
    function getFeed(bytes32 key) external view virtual override returns (address proxy, uint48 maxStaleness) {
        return API3AdapterLib.getFeed(key);
    }

    /// @inheritdoc IAPI3Adapter
    function latestAnswer(bytes32 key) external view virtual override returns (int256 answerWad) {
        return API3AdapterLib.latestAnswer(key);
    }

    /// @inheritdoc IAPI3Adapter
    function read(bytes32 key) external view virtual override returns (int224 value, uint32 timestamp) {
        return API3AdapterLib.read(key);
    }

    /// @inheritdoc IAPI3Adapter
    function registerFeed(bytes32 key, address proxy, uint48 maxStaleness) external virtual override {
        API3AdapterLib.registerFeed(key, proxy, maxStaleness);
    }

    /// @inheritdoc IAPI3Adapter
    function unregisterFeed(bytes32 key) external virtual override {
        API3AdapterLib.unregisterFeed(key);
    }
}
