// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPythEntropyAdapter} from "@lattice/interfaces/IPythEntropyAdapter.sol";
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
}
