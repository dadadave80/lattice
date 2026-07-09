// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPythAdapter} from "@lattice/interfaces/oracles/IPythAdapter.sol";
import {PythAdapterLib} from "@lattice/oracles/libraries/PythAdapterLib.sol";

/// @title PythAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Pyth Network (https://github.com/pyth-network/pyth-crosschain)
/// @notice Diamond facet exposing pull-based Pyth price feeds with per-feed staleness + confidence
///         configuration and WAD-normalized answers. Shares the {IPriceOracleReader} read surface with
///         the other Lattice oracle adapters.
/// @dev Stateless delegator — all logic and storage live in {PythAdapterLib}. Consumers inherit this
///      contract and add AccessControl + an initializer. Prices are refreshed via the payable
///      {updatePriceFeeds}, then read via {latestAnswer}.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Pyth Network
contract PythAdapter is IPythAdapter {
    /// @inheritdoc IPythAdapter
    function pyth() external view virtual override returns (address) {
        return PythAdapterLib.pyth();
    }

    /// @inheritdoc IPythAdapter
    function getFeed(bytes32 key)
        external
        view
        virtual
        override
        returns (bytes32 priceId, uint48 maxStaleness, uint64 maxConfBps)
    {
        return PythAdapterLib.getFeed(key);
    }

    /// @inheritdoc IPythAdapter
    function latestAnswer(bytes32 key) external view virtual override returns (int256 answerWad) {
        return PythAdapterLib.latestAnswer(key);
    }

    /// @inheritdoc IPythAdapter
    function latestAnswerRaw(bytes32 key)
        external
        view
        virtual
        override
        returns (int64 price, int32 expo, uint64 conf, uint256 publishTime)
    {
        return PythAdapterLib.latestAnswerRaw(key);
    }

    /// @inheritdoc IPythAdapter
    function getUpdateFee(bytes[] calldata updateData) external view virtual override returns (uint256) {
        return PythAdapterLib.getUpdateFee(updateData);
    }

    /// @inheritdoc IPythAdapter
    function updatePriceFeeds(bytes[] calldata updateData) external payable virtual override {
        PythAdapterLib.updatePriceFeeds(updateData);
    }

    /// @inheritdoc IPythAdapter
    function setPyth(address pyth_) external virtual override {
        PythAdapterLib.setPyth(pyth_);
    }

    /// @inheritdoc IPythAdapter
    function registerFeed(bytes32 key, bytes32 priceId, uint48 maxStaleness, uint64 maxConfBps)
        external
        virtual
        override
    {
        PythAdapterLib.registerFeed(key, priceId, maxStaleness, maxConfBps);
    }

    /// @inheritdoc IPythAdapter
    function unregisterFeed(bytes32 key) external virtual override {
        PythAdapterLib.unregisterFeed(key);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect PythAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `getFeed(bytes32)` 0x280aebcf
    ///      `getUpdateFee(bytes[])` 0xd47eed45
    ///      `latestAnswer(bytes32)` 0x084d4783
    ///      `latestAnswerRaw(bytes32)` 0xad0ddbee
    ///      `pyth()` 0xf98d06f0
    ///      `registerFeed(bytes32,bytes32,uint48,uint64)` 0xb364e0d4
    ///      `setPyth(address)` 0xee22fd6f
    ///      `unregisterFeed(bytes32)` 0x2a589908
    ///      `updatePriceFeeds(bytes[])` 0xef9e5e28
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"280aebcfd47eed45084d4783ad0ddbeef98d06f0b364e0d4ee22fd6f2a589908ef9e5e28";
    }
}
