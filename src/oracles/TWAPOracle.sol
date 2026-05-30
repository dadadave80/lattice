// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ITWAPOracle} from "@lattice/interfaces/ITWAPOracle.sol";
import {TWAPOracleLib} from "@lattice/oracles/libraries/TWAPOracleLib.sol";

/// @title TWAPOracle
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Diamond facet for a Uniswap V2-style time-weighted average price oracle.
/// @dev Stateless delegator — all logic and storage live in TWAPOracleLib.
///      Consumers inherit this contract and add AccessControl + an initializer.
contract TWAPOracle is ITWAPOracle {
    /// @inheritdoc ITWAPOracle
    function getPair(bytes32 key) external view virtual override returns (address pair) {
        return TWAPOracleLib.getPair(key);
    }

    /// @inheritdoc ITWAPOracle
    function getLatestObservation(bytes32 key) external view virtual override returns (Observation memory) {
        return TWAPOracleLib.getLatestObservation(key);
    }

    /// @inheritdoc ITWAPOracle
    function consult(bytes32 key, uint32 windowSeconds)
        external
        view
        virtual
        override
        returns (uint256 price0Twap, uint256 price1Twap)
    {
        return TWAPOracleLib.consult(key, windowSeconds);
    }

    /// @inheritdoc ITWAPOracle
    function registerPair(bytes32 key, address pair) external virtual override {
        TWAPOracleLib.registerPair(key, pair);
    }

    /// @inheritdoc ITWAPOracle
    function unregisterPair(bytes32 key) external virtual override {
        TWAPOracleLib.unregisterPair(key);
    }

    /// @inheritdoc ITWAPOracle
    function recordObservation(bytes32 key) external virtual override {
        TWAPOracleLib.recordObservation(key);
    }
}
