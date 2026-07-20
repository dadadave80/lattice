// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IStdReference} from "@lattice/interfaces/external/band/IStdReference.sol";
import {IBandAdapter} from "@lattice/interfaces/oracles/IBandAdapter.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.BandAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant BAND_ADAPTER_STORAGE_SLOT = 0xf5012e750700459bfafa131fc1c12ce6e9c0f0209cb29cbc1f960c4760a00a00;

/// @dev 0xebdf87c5 is `type(IBandAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xebdf87c5), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IBANDADAPTER_SLOT = 0xc004cf02eead1d879bc806deefbe1f4228491d4cea98d16c38bf22274d73f5ac;

/// @notice Packed data for a single registered Band feed.
/// @dev APPEND-ONLY. A registered feed has `maxStaleness != 0` (the not-registered sentinel).
struct BandFeed {
    /// @notice Maximum age in seconds before a rate is considered stale.
    uint48 maxStaleness;
    /// @notice The base symbol (e.g. `"ETH"`).
    string base;
    /// @notice The quote symbol (e.g. `"USD"`).
    string quote;
}

/// @notice ERC-7201 namespaced storage for BandAdapter.
/// @dev APPEND-ONLY: new fields may only be added at the end.
/// @custom:storage-location erc7201:lattice.storage.BandAdapter
struct BandAdapterStorage {
    /// @dev feed key => feed config.
    mapping(bytes32 key => BandFeed) _feeds;
    /// @dev the StdReference contract.
    address _reference;
}

/// @title BandAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Band Protocol (https://github.com/bandprotocol)
/// @notice Library wrapping the Band Protocol standard reference oracle with per-feed staleness
///         configuration and WAD normalization, exposing the shared {IPriceOracleReader} read surface.
/// @dev Three-layer pattern: this library holds the logic + namespaced storage; the stateless
///      {BandAdapter} facet forwards to it. Band uses a SINGLE global StdReference contract per chain;
///      reads use `getReferenceData(base, quote)` and validate registration, sign, future timestamp, and
///      staleness on-chain. Band rates are already 1e18-scaled, so normalization only widens
///      `uint256 -> int256`.
library BandAdapterLib {
    function bandAdapterStorage() internal pure returns (BandAdapterStorage storage $) {
        assembly {
            $.slot := BAND_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes BandAdapter with the StdReference contract and registers the ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __BandAdapter_init(address reference_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        if (reference_ == address(0)) revert IBandAdapter.BandReferenceIsZero();
        bandAdapterStorage()._reference = reference_;
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for IBandAdapter.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IBANDADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function stdReference() internal view returns (address) {
        return bandAdapterStorage()._reference;
    }

    function getFeed(bytes32 key) internal view returns (string memory base, string memory quote, uint48 maxStaleness) {
        BandFeed storage f = bandAdapterStorage()._feeds[key];
        return (f.base, f.quote, f.maxStaleness);
    }

    /// @notice Returns the validated raw Band reference data for `key`.
    /// @dev Validates: registration, sign (`rate != 0`), future-timestamp, and staleness. Staleness is
    ///      measured against the older of the two symbol update timestamps.
    function getReferenceData(bytes32 key)
        internal
        view
        returns (uint256 rate, uint256 lastUpdatedBase, uint256 lastUpdatedQuote)
    {
        BandFeed storage f = bandAdapterStorage()._feeds[key];
        if (f.maxStaleness == 0) revert IBandAdapter.BandFeedNotRegistered(key);

        IStdReference.ReferenceData memory rd = IStdReference(_requireReference()).getReferenceData(f.base, f.quote);
        rate = rd.rate;
        lastUpdatedBase = rd.lastUpdatedBase;
        lastUpdatedQuote = rd.lastUpdatedQuote;

        if (rate == 0) revert IBandAdapter.BandInvalidAnswer(key, rate);
        // Staleness is bounded by the older of the two symbol updates.
        uint256 lastUpdated = lastUpdatedBase < lastUpdatedQuote ? lastUpdatedBase : lastUpdatedQuote;
        // Future-timestamp guard (avoids an underflow panic and rejects impossible data); treated as stale.
        if (lastUpdated > block.timestamp || block.timestamp - lastUpdated > f.maxStaleness) {
            revert IBandAdapter.BandStaleData(key, lastUpdated, f.maxStaleness);
        }
    }

    /// @notice Returns the latest rate normalized to 18 decimals (WAD).
    /// @dev Band rates are already 1e18-scaled, so this only widens `uint256 -> int256`. A rate `>= 2^255`
    ///      would wrap to a negative `int256`, so it is rejected rather than cast.
    function latestAnswer(bytes32 key) internal view returns (int256 answerWad) {
        (uint256 rate,,) = getReferenceData(key);
        if (rate > uint256(type(int256).max)) revert IBandAdapter.BandInvalidAnswer(key, rate);
        answerWad = int256(rate);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    function setReference(address reference_) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (reference_ == address(0)) revert IBandAdapter.BandReferenceIsZero();
        bandAdapterStorage()._reference = reference_;
        emit IBandAdapter.ReferenceSet(reference_);
    }

    function registerFeed(bytes32 key, string calldata base, string calldata quote, uint48 maxStaleness) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (bytes(base).length == 0 || bytes(quote).length == 0 || maxStaleness == 0) {
            revert IBandAdapter.BandInvalidConfig();
        }
        bandAdapterStorage()._feeds[key] = BandFeed({maxStaleness: maxStaleness, base: base, quote: quote});
        emit IBandAdapter.FeedRegistered(key, base, quote, maxStaleness);
    }

    function unregisterFeed(bytes32 key) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        delete bandAdapterStorage()._feeds[key];
        emit IBandAdapter.FeedUnregistered(key);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    function _requireReference() private view returns (address r) {
        r = bandAdapterStorage()._reference;
        if (r == address(0)) revert IBandAdapter.BandReferenceNotSet();
    }
}
