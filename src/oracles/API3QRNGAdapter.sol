// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAPI3QRNGAdapter} from "@lattice/interfaces/IAPI3QRNGAdapter.sol";
import {API3QRNGAdapterLib} from "@lattice/oracles/libraries/API3QRNGAdapterLib.sol";

/// @title API3QRNGAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from API3 (https://github.com/api3dao/airnode)
/// @notice Diamond facet for API3 QRNG (quantum randomness) over the Airnode
///         Request-Response Protocol (self-sponsoring).
/// @dev Stateless delegator — all logic and storage live in API3QRNGAdapterLib.
///
///      This facet handles the request/track layer only.  Consumer facets that
///      inherit this contract should override `fulfillRandomNumber` to act on
///      delivered randomness after calling `super.fulfillRandomNumber`.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source API3
contract API3QRNGAdapter is IAPI3QRNGAdapter {
    /// @inheritdoc IAPI3QRNGAdapter
    function getConfig() external view virtual override returns (QRNGConfig memory) {
        return API3QRNGAdapterLib.getConfig();
    }

    /// @inheritdoc IAPI3QRNGAdapter
    function getUserKey(bytes32 requestId) external view virtual override returns (bytes32) {
        return API3QRNGAdapterLib.getUserKey(requestId);
    }

    /// @inheritdoc IAPI3QRNGAdapter
    function setConfig(QRNGConfig calldata config) external virtual override {
        API3QRNGAdapterLib.setConfig(config);
    }

    /// @inheritdoc IAPI3QRNGAdapter
    function setSelfSponsorship(bool status) external virtual override {
        API3QRNGAdapterLib.setSelfSponsorship(status);
    }

    /// @inheritdoc IAPI3QRNGAdapter
    function requestRandomNumber(bytes32 userKey) external virtual override returns (bytes32 requestId) {
        return API3QRNGAdapterLib.requestRandomNumber(userKey);
    }

    /// @inheritdoc IAPI3QRNGAdapter
    function fulfillRandomNumber(bytes32 requestId, bytes calldata data) external virtual override {
        API3QRNGAdapterLib.fulfillRandomNumber(requestId, data);
    }
}
