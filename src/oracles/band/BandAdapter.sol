// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IBandAdapter} from "@lattice/interfaces/oracles/IBandAdapter.sol";
import {BandAdapterLib} from "@lattice/oracles/band/BandAdapterLib.sol";

/// @title BandAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Band Protocol (https://github.com/bandprotocol)
/// @notice Diamond facet that reads Band Protocol reference data through the single global StdReference
///         contract with per-feed staleness configuration and WAD-normalized answers. Shares the
///         {IPriceOracleReader} read surface with the other Lattice oracle adapters.
/// @dev Stateless delegator — all logic and storage live in {BandAdapterLib}. Consumers inherit this
///      contract and add AccessControl + an initializer.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Band
contract BandAdapter is IBandAdapter {
    /// @inheritdoc IBandAdapter
    function stdReference() external view virtual override returns (address) {
        return BandAdapterLib.stdReference();
    }

    /// @inheritdoc IBandAdapter
    function getFeed(bytes32 key)
        external
        view
        virtual
        override
        returns (string memory base, string memory quote, uint48 maxStaleness)
    {
        return BandAdapterLib.getFeed(key);
    }

    /// @inheritdoc IBandAdapter
    function latestAnswer(bytes32 key) external view virtual override returns (int256 answerWad) {
        return BandAdapterLib.latestAnswer(key);
    }

    /// @inheritdoc IBandAdapter
    function getReferenceData(bytes32 key)
        external
        view
        virtual
        override
        returns (uint256 rate, uint256 lastUpdatedBase, uint256 lastUpdatedQuote)
    {
        return BandAdapterLib.getReferenceData(key);
    }

    /// @inheritdoc IBandAdapter
    function setReference(address reference_) external virtual override {
        BandAdapterLib.setReference(reference_);
    }

    /// @inheritdoc IBandAdapter
    function registerFeed(bytes32 key, string calldata base, string calldata quote, uint48 maxStaleness)
        external
        virtual
        override
    {
        BandAdapterLib.registerFeed(key, base, quote, maxStaleness);
    }

    /// @inheritdoc IBandAdapter
    function unregisterFeed(bytes32 key) external virtual override {
        BandAdapterLib.unregisterFeed(key);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect BandAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `getFeed(bytes32)` 0x280aebcf
    ///      `getReferenceData(bytes32)` 0x182400b9
    ///      `latestAnswer(bytes32)` 0x084d4783
    ///      `registerFeed(bytes32,string,string,uint48)` 0xcf3f0bd3
    ///      `setReference(address)` 0x34bdf2c4
    ///      `stdReference()` 0x02664b2f
    ///      `unregisterFeed(bytes32)` 0x2a589908
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"280aebcf182400b9084d4783cf3f0bd334bdf2c402664b2f2a589908";
    }
}
