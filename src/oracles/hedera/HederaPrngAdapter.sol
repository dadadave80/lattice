// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IHederaPrngAdapter} from "@lattice/interfaces/oracles/IHederaPrngAdapter.sol";
import {HederaPrngAdapterLib} from "@lattice/oracles/hedera/HederaPrngAdapterLib.sol";

/// @title HederaPrngAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from hiero-ledger/hiero-contracts (https://github.com/hiero-ledger/hiero-contracts)
/// @notice Diamond facet exposing Hedera's PRNG system contract (0x169) as synchronous randomness.
/// @dev Stateless delegator over HederaPrngAdapterLib. Only meaningful on Hedera.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Hedera
contract HederaPrngAdapter is IHederaPrngAdapter {
    /// @inheritdoc IHederaPrngAdapter
    function drawSeed() external virtual override returns (bytes32 seed) {
        return HederaPrngAdapterLib.drawSeed();
    }

    /// @inheritdoc IHederaPrngAdapter
    function drawInRange(uint32 lo, uint32 hi) external virtual override returns (uint32 number) {
        return HederaPrngAdapterLib.drawInRange(lo, hi);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643). Order matches `forge inspect HederaPrngAdapter
    ///      methodIdentifiers` (alphabetical by signature); kept in exact parity by ExportSelectorsParityTest. Chunks:
    ///      `drawInRange(uint32,uint32)` 0xc2f9516d
    ///      `drawSeed()` 0x4c7dde2f
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"c2f9516d4c7dde2f";
    }
}
