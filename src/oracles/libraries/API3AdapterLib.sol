// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IApi3Proxy} from "@lattice/interfaces/external/IApi3Proxy.sol";
import {IAPI3Adapter} from "@lattice/interfaces/oracles/IAPI3Adapter.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.API3Adapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant API3_ADAPTER_STORAGE_SLOT = 0xdedf34315ce34cb136d15a8f1bef434dfd97b5e1960d065caa42769bce24e700;

/// @dev 0xfa98111e is `type(IAPI3Adapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xfa98111e), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IAPI3ADAPTER_SLOT = 0x21168d66e590ee042a818ed855046fa88c4c6601cbf29cfcb9e870d054a8cb77;

/// @notice Packed data for a single registered dAPI feed.
/// @dev APPEND-ONLY. A registered feed has `proxy != address(0)` (the not-registered sentinel).
struct API3Feed {
    /// @notice The dAPI reader proxy address.
    address proxy;
    /// @notice Maximum age in seconds before a value is considered stale.
    uint48 maxStaleness;
}

/// @notice ERC-7201 namespaced storage for API3Adapter.
/// @dev APPEND-ONLY: new fields may only be added at the end.
/// @custom:storage-location erc7201:lattice.storage.API3Adapter
struct API3AdapterStorage {
    /// @dev feed key => feed config.
    mapping(bytes32 key => API3Feed) _feeds;
}

/// @title API3AdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from API3 (https://github.com/api3dao/contracts)
/// @notice Library wrapping API3 dAPI reader proxies with per-feed staleness configuration, exposing the
///         shared {IPriceOracleReader} read surface.
/// @dev Three-layer pattern: this library holds the logic + namespaced storage; the stateless
///      {API3Adapter} facet forwards to it. dAPI values are already 18-decimals (WAD), so normalization
///      only widens `int224 -> int256`; reads validate sign, future timestamp, and staleness on-chain.
library API3AdapterLib {
    function api3AdapterStorage() internal pure returns (API3AdapterStorage storage $) {
        assembly {
            $.slot := API3_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IAPI3Adapter ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __API3Adapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for IAPI3Adapter.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IAPI3ADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function getFeed(bytes32 key) internal view returns (address proxy, uint48 maxStaleness) {
        API3Feed storage f = api3AdapterStorage()._feeds[key];
        return (f.proxy, f.maxStaleness);
    }

    /// @notice Returns the validated raw dAPI value (native int224) and its update timestamp.
    /// @dev Validates: registration, sign (`value > 0`), future-timestamp, and staleness.
    function read(bytes32 key) internal view returns (int224 value, uint32 timestamp) {
        API3Feed storage f = api3AdapterStorage()._feeds[key];
        if (f.proxy == address(0)) revert IAPI3Adapter.API3FeedNotRegistered(key);

        (value, timestamp) = IApi3Proxy(f.proxy).read();

        if (value <= 0) revert IAPI3Adapter.API3InvalidAnswer(key, value);
        // Future-timestamp guard (avoids an underflow panic and rejects impossible data); treated as stale.
        if (timestamp > block.timestamp || block.timestamp - timestamp > f.maxStaleness) {
            revert IAPI3Adapter.API3StaleData(key, timestamp, f.maxStaleness);
        }
    }

    /// @notice Returns the latest dAPI value normalized to 18 decimals (WAD).
    /// @dev dAPI values are already 1e18-scaled, so this only widens `int224 -> int256`.
    function latestAnswer(bytes32 key) internal view returns (int256 answerWad) {
        (int224 value,) = read(key);
        answerWad = int256(value);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    function registerFeed(bytes32 key, address proxy, uint48 maxStaleness) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (proxy == address(0) || maxStaleness == 0) revert IAPI3Adapter.API3InvalidConfig();
        api3AdapterStorage()._feeds[key] = API3Feed({proxy: proxy, maxStaleness: maxStaleness});
        emit IAPI3Adapter.FeedRegistered(key, proxy, maxStaleness);
    }

    function unregisterFeed(bytes32 key) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        delete api3AdapterStorage()._feeds[key];
        emit IAPI3Adapter.FeedUnregistered(key);
    }
}
