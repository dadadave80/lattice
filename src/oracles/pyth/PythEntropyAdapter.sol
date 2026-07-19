// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPythEntropyAdapter} from "@lattice/interfaces/oracles/IPythEntropyAdapter.sol";
import {PythEntropyAdapterLib} from "@lattice/oracles/libraries/PythEntropyAdapterLib.sol";

/// @title PythEntropyAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Pyth (https://github.com/pyth-network/pyth-crosschain)
/// @notice Diamond facet for Pyth Entropy on-demand (commit/reveal) randomness.
/// @dev Stateless delegator — all logic and storage live in PythEntropyAdapterLib.
///
///      This facet handles the request/track layer only. Consumer facets that inherit this contract
///      should override `entropyCallback` to act on delivered randomness after calling
///      `super.entropyCallback`.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Pyth
contract PythEntropyAdapter is IPythEntropyAdapter {
    /// @inheritdoc IPythEntropyAdapter
    function getConfig() external view virtual override returns (EntropyConfig memory) {
        return PythEntropyAdapterLib.getConfig();
    }

    /// @inheritdoc IPythEntropyAdapter
    function getFee() external view virtual override returns (uint256) {
        return PythEntropyAdapterLib.getFee();
    }

    /// @inheritdoc IPythEntropyAdapter
    function getUserKey(uint64 sequenceNumber) external view virtual override returns (bytes32) {
        return PythEntropyAdapterLib.getUserKey(sequenceNumber);
    }

    /// @inheritdoc IPythEntropyAdapter
    function setConfig(EntropyConfig calldata config) external virtual override {
        PythEntropyAdapterLib.setConfig(config);
    }

    /// @inheritdoc IPythEntropyAdapter
    function requestRandomNumber(bytes32 userKey, bytes32 userRandomNumber)
        external
        payable
        virtual
        override
        returns (uint64 sequenceNumber)
    {
        return PythEntropyAdapterLib.requestRandomNumber(userKey, userRandomNumber);
    }

    /// @inheritdoc IPythEntropyAdapter
    function entropyCallback(uint64 sequence, address provider, bytes32 randomNumber) external virtual override {
        PythEntropyAdapterLib.entropyCallback(sequence, provider, randomNumber);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect PythEntropyAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `entropyCallback(uint64,address,bytes32)` 0x24185135
    ///      `getConfig()` 0xc3f909d4
    ///      `getFee()` 0xced72f87
    ///      `getUserKey(uint64)` 0x65b56cd4
    ///      `requestRandomNumber(bytes32,bytes32)` 0x8738559f
    ///      `setConfig((address,address))` 0x861fb568
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"24185135c3f909d4ced72f8765b56cd48738559f861fb568";
    }
}
