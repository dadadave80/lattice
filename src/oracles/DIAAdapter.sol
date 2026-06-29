// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDIAAdapter} from "@lattice/interfaces/oracles/IDIAAdapter.sol";
import {DIAAdapterLib} from "@lattice/oracles/libraries/DIAAdapterLib.sol";

/// @title DIAAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from DIA (https://github.com/diadata-org)
/// @notice Diamond facet that reads DIA OracleV2 price feeds through their string-keyed `getValue` API
///         with per-feed staleness configuration and WAD-normalized answers.
/// @dev Stateless delegator — all logic and storage live in {DIAAdapterLib}. Consumers inherit this
///      contract and add AccessControl + an initializer.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source DIA
contract DIAAdapter is IDIAAdapter {
    /// @inheritdoc IDIAAdapter
    function getFeed(bytes32 key)
        external
        view
        virtual
        override
        returns (address oracle, string memory diaKey, uint48 maxStaleness)
    {
        return DIAAdapterLib.getFeed(key);
    }

    /// @inheritdoc IDIAAdapter
    function latestAnswer(bytes32 key) external view virtual override returns (int256 answerWad) {
        return DIAAdapterLib.latestAnswer(key);
    }

    /// @inheritdoc IDIAAdapter
    function getValue(bytes32 key) external view virtual override returns (uint128 value, uint128 timestamp) {
        return DIAAdapterLib.getValue(key);
    }

    /// @inheritdoc IDIAAdapter
    function registerFeed(bytes32 key, address oracle, string calldata diaKey, uint48 maxStaleness)
        external
        virtual
        override
    {
        DIAAdapterLib.registerFeed(key, oracle, diaKey, maxStaleness);
    }

    /// @inheritdoc IDIAAdapter
    function unregisterFeed(bytes32 key) external virtual override {
        DIAAdapterLib.unregisterFeed(key);
    }
}
