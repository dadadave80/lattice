// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAPI3QRNGAdapter} from "@lattice/interfaces/oracles/IAPI3QRNGAdapter.sol";
import {API3QRNGAdapterLib} from "@lattice/oracles/api3/API3QRNGAdapterLib.sol";

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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect API3QRNGAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `fulfillRandomNumber(bytes32,bytes)` 0xf43a72e3
    ///      `getConfig()` 0xc3f909d4
    ///      `getUserKey(bytes32)` 0xa1cfedf0
    ///      `requestRandomNumber(bytes32)` 0xbd313d78
    ///      `setConfig((address,address,bytes32,address))` 0xa601dfb6
    ///      `setSelfSponsorship(bool)` 0x230bc58e
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"f43a72e3c3f909d4a1cfedf0bd313d78a601dfb6230bc58e";
    }
}
