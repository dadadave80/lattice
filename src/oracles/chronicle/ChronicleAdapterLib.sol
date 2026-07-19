// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IChronicle} from "@lattice/interfaces/external/chronicle/IChronicle.sol";
import {IChronicleAdapter} from "@lattice/interfaces/oracles/IChronicleAdapter.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ChronicleAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant CHRONICLE_ADAPTER_STORAGE_SLOT = 0xfc08f646a4b61c410e914db3efd5dca6935b089749eb55e38d0c450dddbb7600;

/// @dev 0x278f5b6a is `type(IChronicleAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x278f5b6a), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ICHRONICLEADAPTER_SLOT = 0xfbb4f19de9230b60c572e8ff078c06c8112306947245c1d5058d08359436c1ca;

/// @notice Packed data for a single registered Chronicle feed.
/// @dev APPEND-ONLY. A registered feed has `chronicle != address(0)` (the not-registered sentinel).
struct ChronicleFeed {
    /// @notice The Chronicle oracle contract address.
    address chronicle;
    /// @notice Maximum age in seconds before a value is considered stale.
    uint48 maxStaleness;
}

/// @notice ERC-7201 namespaced storage for ChronicleAdapter.
/// @dev APPEND-ONLY: new fields may only be added at the end.
/// @custom:storage-location erc7201:lattice.storage.ChronicleAdapter
struct ChronicleAdapterStorage {
    /// @dev feed key => feed config.
    mapping(bytes32 key => ChronicleFeed) _feeds;
}

/// @title ChronicleAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Chronicle (https://github.com/chronicleprotocol)
/// @notice Library wrapping Chronicle oracle feeds with per-feed staleness configuration, exposing the
///         shared {IPriceOracleReader} read surface.
/// @dev Three-layer pattern: this library holds the logic + namespaced storage; the stateless
///      {ChronicleAdapter} facet forwards to it. Chronicle values are already 18-decimals (WAD), so
///      normalization only casts `uint256 -> int256` (no rescaling); reads validate zero value, future
///      age, and staleness on-chain. Chronicle feeds are toll-gated (Schnorr-signed): the adapter contract
///      must be `kiss`ed by the oracle operator before reads will succeed.
library ChronicleAdapterLib {
    function chronicleAdapterStorage() internal pure returns (ChronicleAdapterStorage storage $) {
        assembly {
            $.slot := CHRONICLE_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IChronicleAdapter ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __ChronicleAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for IChronicleAdapter.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ICHRONICLEADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function getFeed(bytes32 key) internal view returns (address chronicle, uint48 maxStaleness) {
        ChronicleFeed storage f = chronicleAdapterStorage()._feeds[key];
        return (f.chronicle, f.maxStaleness);
    }

    /// @notice Returns the validated raw Chronicle value and the timestamp it was last written on-chain.
    /// @dev Validates: registration, non-zero value, future-age guard, and staleness.
    ///      Chronicle values are uint256 WAD; zero is the invalid-data sentinel (price can never be 0).
    function readWithAge(bytes32 key) internal view returns (uint256 value, uint256 age) {
        ChronicleFeed storage f = chronicleAdapterStorage()._feeds[key];
        if (f.chronicle == address(0)) revert IChronicleAdapter.ChronicleFeedNotRegistered(key);

        (value, age) = IChronicle(f.chronicle).readWithAge();

        if (value == 0) revert IChronicleAdapter.ChronicleInvalidAnswer(key, value);
        // Future-age guard (avoids an underflow panic and rejects impossible data); treated as stale.
        if (age > block.timestamp || block.timestamp - age > f.maxStaleness) {
            revert IChronicleAdapter.ChronicleStaleData(key, age, f.maxStaleness);
        }
    }

    /// @notice Returns the latest Chronicle value normalized to 18 decimals (WAD).
    /// @dev Chronicle values are already 1e18-scaled, so this only casts `uint256 -> int256`. A value
    ///      `>= 2^255` would wrap to a negative `int256`, so it is rejected rather than cast.
    function latestAnswer(bytes32 key) internal view returns (int256 answerWad) {
        (uint256 value,) = readWithAge(key);
        if (value > uint256(type(int256).max)) revert IChronicleAdapter.ChronicleInvalidAnswer(key, value);
        answerWad = int256(value);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    function registerFeed(bytes32 key, address chronicle, uint48 maxStaleness) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (chronicle == address(0) || maxStaleness == 0) revert IChronicleAdapter.ChronicleInvalidConfig();
        chronicleAdapterStorage()._feeds[key] = ChronicleFeed({chronicle: chronicle, maxStaleness: maxStaleness});
        emit IChronicleAdapter.FeedRegistered(key, chronicle, maxStaleness);
    }

    function unregisterFeed(bytes32 key) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        delete chronicleAdapterStorage()._feeds[key];
        emit IChronicleAdapter.FeedUnregistered(key);
    }
}
