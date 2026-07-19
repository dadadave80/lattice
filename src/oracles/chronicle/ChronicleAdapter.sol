// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IChronicleAdapter} from "@lattice/interfaces/oracles/IChronicleAdapter.sol";
import {ChronicleAdapterLib} from "@lattice/oracles/chronicle/ChronicleAdapterLib.sol";

/// @title ChronicleAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Chronicle (https://github.com/chronicleprotocol)
/// @notice Diamond facet that reads Chronicle oracle feeds through their per-feed oracle contracts with
///         per-feed staleness configuration and WAD-normalized answers.
/// @dev Stateless delegator — all logic and storage live in {ChronicleAdapterLib}. Consumers inherit this
///      contract and add AccessControl + an initializer. Chronicle feeds are Schnorr-signed and toll-gated:
///      the deployed adapter contract must be `kiss`ed by the oracle operator before reads will succeed.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Chronicle
contract ChronicleAdapter is IChronicleAdapter {
    /// @inheritdoc IChronicleAdapter
    function getFeed(bytes32 key) external view virtual override returns (address chronicle, uint48 maxStaleness) {
        return ChronicleAdapterLib.getFeed(key);
    }

    /// @inheritdoc IChronicleAdapter
    function latestAnswer(bytes32 key) external view virtual override returns (int256 answerWad) {
        return ChronicleAdapterLib.latestAnswer(key);
    }

    /// @inheritdoc IChronicleAdapter
    function readWithAge(bytes32 key) external view virtual override returns (uint256 value, uint256 age) {
        return ChronicleAdapterLib.readWithAge(key);
    }

    /// @inheritdoc IChronicleAdapter
    function registerFeed(bytes32 key, address chronicle, uint48 maxStaleness) external virtual override {
        ChronicleAdapterLib.registerFeed(key, chronicle, maxStaleness);
    }

    /// @inheritdoc IChronicleAdapter
    function unregisterFeed(bytes32 key) external virtual override {
        ChronicleAdapterLib.unregisterFeed(key);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ChronicleAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `getFeed(bytes32)` 0x280aebcf
    ///      `latestAnswer(bytes32)` 0x084d4783
    ///      `readWithAge(bytes32)` 0xbccd5e4d
    ///      `registerFeed(bytes32,address,uint48)` 0x915d3063
    ///      `unregisterFeed(bytes32)` 0x2a589908
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"280aebcf084d4783bccd5e4d915d30632a589908";
    }
}
