// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ITWAPOracle} from "@lattice/interfaces/oracles/ITWAPOracle.sol";
import {TWAPOracleLib} from "@lattice/oracles/uniswap/TWAPOracleLib.sol";

/// @title TWAPOracle
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Uniswap V2 (https://github.com/Uniswap/v2-periphery/blob/master/contracts/examples/ExampleSlidingWindowOracle.sol)
/// @notice Diamond facet for a Uniswap V2-style time-weighted average price oracle.
/// @dev Stateless delegator — all logic and storage live in TWAPOracleLib.
///      Consumers inherit this contract and add AccessControl + an initializer.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Uniswap V2
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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect TWAPOracle methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `consult(bytes32,uint32)` 0x47473b00
    ///      `getLatestObservation(bytes32)` 0x43542636
    ///      `getPair(bytes32)` 0xb8e5303d
    ///      `recordObservation(bytes32)` 0x06bd6d1e
    ///      `registerPair(bytes32,address)` 0x64b7e622
    ///      `unregisterPair(bytes32)` 0x0f464dd7
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"47473b0043542636b8e5303d06bd6d1e64b7e6220f464dd7";
    }
}
