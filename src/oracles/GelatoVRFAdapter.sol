// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IGelatoVRFAdapter} from "@lattice/interfaces/oracles/IGelatoVRFAdapter.sol";
import {GelatoVRFAdapterLib} from "@lattice/oracles/libraries/GelatoVRFAdapterLib.sol";

/// @title GelatoVRFAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Gelato (https://github.com/gelatodigital/vrf-contracts)
/// @notice Diamond facet for Gelato VRF (drand-backed) randomness — no on-chain fee.
/// @dev Stateless delegator — all logic and storage live in GelatoVRFAdapterLib.
///
///      This facet handles the request/track layer only.  Consumer facets that
///      inherit this contract should override `fulfillRandomness` to act on
///      delivered randomness after calling `super.fulfillRandomness`.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Gelato
contract GelatoVRFAdapter is IGelatoVRFAdapter {
    /// @inheritdoc IGelatoVRFAdapter
    function getOperator() external view virtual override returns (address) {
        return GelatoVRFAdapterLib.getOperator();
    }

    /// @inheritdoc IGelatoVRFAdapter
    function getUserKey(uint256 requestId) external view virtual override returns (bytes32) {
        return GelatoVRFAdapterLib.getUserKey(requestId);
    }

    /// @inheritdoc IGelatoVRFAdapter
    function setOperator(address operator) external virtual override {
        GelatoVRFAdapterLib.setOperator(operator);
    }

    /// @inheritdoc IGelatoVRFAdapter
    function requestRandomness(bytes32 userKey) external virtual override returns (uint256 requestId) {
        return GelatoVRFAdapterLib.requestRandomness(userKey);
    }

    /// @inheritdoc IGelatoVRFAdapter
    function fulfillRandomness(uint256 randomness, bytes calldata dataWithRound) external virtual override {
        GelatoVRFAdapterLib.fulfillRandomness(randomness, dataWithRound);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect GelatoVRFAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `fulfillRandomness(uint256,bytes)` 0xb3f6b99a
    ///      `getOperator()` 0xe7f43c68
    ///      `getUserKey(uint256)` 0xdd1e2651
    ///      `requestRandomness(bytes32)` 0x5e3b709f
    ///      `setOperator(address)` 0xb3ab15fb
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"b3f6b99ae7f43c68dd1e26515e3b709fb3ab15fb";
    }
}
