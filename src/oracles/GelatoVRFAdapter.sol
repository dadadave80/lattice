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
}
