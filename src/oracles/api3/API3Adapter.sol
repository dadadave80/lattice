// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAPI3Adapter} from "@lattice/interfaces/oracles/IAPI3Adapter.sol";
import {API3AdapterLib} from "@lattice/oracles/api3/API3AdapterLib.sol";

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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect API3Adapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `getFeed(bytes32)` 0x280aebcf
    ///      `latestAnswer(bytes32)` 0x084d4783
    ///      `read(bytes32)` 0x61da1439
    ///      `registerFeed(bytes32,address,uint48)` 0x915d3063
    ///      `unregisterFeed(bytes32)` 0x2a589908
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"280aebcf084d478361da1439915d30632a589908";
    }
}
