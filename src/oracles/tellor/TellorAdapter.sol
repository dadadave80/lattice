// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ITellorAdapter} from "@lattice/interfaces/oracles/ITellorAdapter.sol";
import {TellorAdapterLib} from "@lattice/oracles/tellor/TellorAdapterLib.sol";

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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect TellorAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `getDataBefore(bytes32)` 0xd196aaee
    ///      `getFeed(bytes32)` 0x280aebcf
    ///      `latestAnswer(bytes32)` 0x084d4783
    ///      `registerFeed(bytes32,bytes32,uint48,uint48)` 0x249fb496
    ///      `setTellor(address)` 0x3b88e4ad
    ///      `tellor()` 0x1959ad5b
    ///      `unregisterFeed(bytes32)` 0x2a589908
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"d196aaee280aebcf084d4783249fb4963b88e4ad1959ad5b2a589908";
    }
}
