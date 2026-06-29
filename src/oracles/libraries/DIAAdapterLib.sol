// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IDIAOracleV2} from "@lattice/interfaces/external/IDIAOracleV2.sol";
import {IDIAAdapter} from "@lattice/interfaces/oracles/IDIAAdapter.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.DIAAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant DIA_ADAPTER_STORAGE_SLOT = 0x96676e4e566fe60ae3185e7bd982de2eb1f4d0f9b85c8e29200af4e575d6c400;

/// @dev 0xec319d60 is `type(IDIAAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xec319d60), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IDIAADAPTER_SLOT = 0xac3b2e96bffda1d6525b62f471f6722940d02b7c74a1e8090cae939120be2443;

/// @notice Packed data for a single registered DIA price feed.
/// @dev APPEND-ONLY. A registered feed has `oracle != address(0)` (the not-registered sentinel).
///      `string diaKey` is placed last to avoid tight-packing complications with dynamic types.
struct DIAFeed {
    /// @notice The DIA OracleV2 contract address.
    address oracle;
    /// @notice Maximum age in seconds before a value is considered stale.
    uint48 maxStaleness;
    /// @notice The DIA price key string (e.g. "ETH/USD").
    string diaKey;
}

/// @notice ERC-7201 namespaced storage for DIAAdapter.
/// @dev APPEND-ONLY: new fields may only be added at the end.
/// @custom:storage-location erc7201:lattice.storage.DIAAdapter
struct DIAAdapterStorage {
    /// @dev feed key => feed config.
    mapping(bytes32 key => DIAFeed) _feeds;
}

/// @title DIAAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from DIA (https://github.com/diadata-org)
/// @notice Library wrapping DIA OracleV2 price feeds with per-feed staleness configuration, exposing the
///         shared {IPriceOracleReader} read surface.
/// @dev Three-layer pattern: this library holds the logic + namespaced storage; the stateless
///      {DIAAdapter} facet forwards to it. DIA values have 8 decimals and are normalized to 18 decimals
///      (WAD) by multiplying by 1e10; reads validate zero value, future timestamp, and staleness on-chain.
library DIAAdapterLib {
    function diaAdapterStorage() internal pure returns (DIAAdapterStorage storage $) {
        assembly {
            $.slot := DIA_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IDIAAdapter ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __DIAAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for IDIAAdapter.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IDIAADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function getFeed(bytes32 key) internal view returns (address oracle, string memory diaKey, uint48 maxStaleness) {
        DIAFeed storage f = diaAdapterStorage()._feeds[key];
        return (f.oracle, f.diaKey, f.maxStaleness);
    }

    /// @notice Returns the validated raw DIA value (native uint128) and its update timestamp.
    /// @dev Validates: registration, zero-value, future-timestamp, and staleness.
    function getValue(bytes32 key) internal view returns (uint128 value, uint128 timestamp) {
        DIAFeed storage f = diaAdapterStorage()._feeds[key];
        if (f.oracle == address(0)) revert IDIAAdapter.DIAFeedNotRegistered(key);

        (value, timestamp) = IDIAOracleV2(f.oracle).getValue(f.diaKey);

        if (value == 0) revert IDIAAdapter.DIAInvalidAnswer(key, value);
        // Future-timestamp guard (avoids an underflow panic and rejects impossible data); treated as stale.
        if (timestamp > block.timestamp || block.timestamp - timestamp > f.maxStaleness) {
            revert IDIAAdapter.DIAStaleData(key, timestamp, f.maxStaleness);
        }
    }

    /// @notice Returns the latest DIA value normalized to 18 decimals (WAD).
    /// @dev DIA values have 8 decimals; multiplying by 1e10 scales them to WAD.
    function latestAnswer(bytes32 key) internal view returns (int256 answerWad) {
        (uint128 value,) = getValue(key);
        answerWad = int256(uint256(value)) * 1e10;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    function registerFeed(bytes32 key, address oracle, string calldata diaKey, uint48 maxStaleness) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (oracle == address(0) || bytes(diaKey).length == 0 || maxStaleness == 0) {
            revert IDIAAdapter.DIAInvalidConfig();
        }
        diaAdapterStorage()._feeds[key] = DIAFeed({oracle: oracle, maxStaleness: maxStaleness, diaKey: diaKey});
        emit IDIAAdapter.FeedRegistered(key, oracle, diaKey, maxStaleness);
    }

    function unregisterFeed(bytes32 key) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        delete diaAdapterStorage()._feeds[key];
        emit IDIAAdapter.FeedUnregistered(key);
    }
}
