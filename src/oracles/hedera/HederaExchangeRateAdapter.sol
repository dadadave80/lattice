// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IHederaExchangeRateAdapter} from "@lattice/interfaces/oracles/IHederaExchangeRateAdapter.sol";
import {HederaExchangeRateAdapterLib} from "@lattice/oracles/hedera/HederaExchangeRateAdapterLib.sol";

/// @title HederaExchangeRateAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from hiero-ledger/hiero-contracts (https://github.com/hiero-ledger/hiero-contracts)
/// @notice Diamond facet exposing Hedera's network USD/HBAR exchange rate (system contract 0x168).
/// @dev Stateless delegator over HederaExchangeRateAdapterLib. Only meaningful on Hedera.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Hedera
contract HederaExchangeRateAdapter is IHederaExchangeRateAdapter {
    /// @inheritdoc IHederaExchangeRateAdapter
    function tinycentsToTinybars(uint256 tinycents) external view virtual override returns (uint256 tinybars) {
        return HederaExchangeRateAdapterLib.tinycentsToTinybars(tinycents);
    }

    /// @inheritdoc IHederaExchangeRateAdapter
    function tinybarsToTinycents(uint256 tinybars) external view virtual override returns (uint256 tinycents) {
        return HederaExchangeRateAdapterLib.tinybarsToTinycents(tinybars);
    }

    /// @inheritdoc IHederaExchangeRateAdapter
    function usdCentsToWei(uint256 cents) external view virtual override returns (uint256 weibar) {
        return HederaExchangeRateAdapterLib.usdCentsToWei(cents);
    }

    /// @inheritdoc IHederaExchangeRateAdapter
    function hbarUsdWad() external view virtual override returns (uint256 priceWad) {
        return HederaExchangeRateAdapterLib.hbarUsdWad();
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643). Order matches `forge inspect HederaExchangeRateAdapter
    ///      methodIdentifiers` (alphabetical by signature); kept in exact parity by ExportSelectorsParityTest. Chunks:
    ///      `hbarUsdWad()` 0xa26c8e04
    ///      `tinybarsToTinycents(uint256)` 0x43a88229
    ///      `tinycentsToTinybars(uint256)` 0x2e3cff6a
    ///      `usdCentsToWei(uint256)` 0x8f66af92
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"a26c8e0443a882292e3cff6a8f66af92";
    }
}
