// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IRedStoneAdapter} from "@lattice/interfaces/IRedStoneAdapter.sol";
import {IRedstonePriceFeedsAdapter} from "@lattice/interfaces/external/IRedstonePriceFeedsAdapter.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.RedStoneAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant REDSTONE_ADAPTER_STORAGE_SLOT = 0x6c77ff7037fedb1e7737bf925fac4c87e7cc2c960916dee7790d2d73271bc700;

/// @dev 0xd5afaecd is `type(IRedStoneAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xd5afaecd), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IREDSTONEADAPTER_SLOT = 0x48fa637c6327d1b003860a80c88da58028cdc6c0ad566c17cfe6e68792096327;

/// @notice Packed data for a single registered RedStone feed.
/// @dev APPEND-ONLY. A registered feed has `adapter != address(0)` (the not-registered sentinel).
struct RedStoneFeed {
    /// @notice The RedStone PriceFeedsAdapter contract address.
    address adapter;
    /// @notice Maximum age in seconds before a value is considered stale.
    uint48 maxStaleness;
    /// @notice The RedStone data-feed id.
    bytes32 dataFeedId;
}

/// @notice ERC-7201 namespaced storage for RedStoneAdapter.
/// @dev APPEND-ONLY: new fields may only be added at the end.
/// @custom:storage-location erc7201:lattice.storage.RedStoneAdapter
struct RedStoneAdapterStorage {
    /// @dev feed key => feed config.
    mapping(bytes32 key => RedStoneFeed) _feeds;
}

/// @title RedStoneAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from RedStone (https://github.com/redstone-finance/redstone-oracles-monorepo)
/// @notice Library wrapping RedStone Push price-feed adapters with per-feed staleness configuration,
///         exposing the shared {IPriceOracleReader} read surface.
/// @dev Three-layer pattern: this library holds the logic + namespaced storage; the stateless
///      {RedStoneAdapter} facet forwards to it. Reads use the RedStone PriceFeedsAdapter's
///      `getValueForDataFeed` (8 decimals) with the batch update time from `getTimestampsFromLatestUpdate`,
///      and validate zero value, future timestamp, and staleness on-chain. Targets the RedStone **Push**
///      model; the **Core**/pull (calldata-injection) model is a separate follow-up.
library RedStoneAdapterLib {
    /// @dev RedStone Push values carry 8 decimals; scale to 18 (WAD) by 1e10.
    uint256 private constant WAD_SCALE = 1e10;

    function redStoneAdapterStorage() internal pure returns (RedStoneAdapterStorage storage $) {
        assembly {
            $.slot := REDSTONE_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IRedStoneAdapter ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __RedStoneAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for IRedStoneAdapter.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IREDSTONEADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function getFeed(bytes32 key) internal view returns (address adapter, bytes32 dataFeedId, uint48 maxStaleness) {
        RedStoneFeed storage f = redStoneAdapterStorage()._feeds[key];
        return (f.adapter, f.dataFeedId, f.maxStaleness);
    }

    /// @notice Returns the validated raw RedStone value (8 decimals) and the batch update timestamp.
    /// @dev Validates: registration, non-zero value, future-timestamp, and staleness. Staleness uses the
    ///      adapter's seconds-based `blockTimestamp` from the latest batch update.
    function getValueForDataFeed(bytes32 key) internal view returns (uint256 value, uint256 timestamp) {
        RedStoneFeed storage f = redStoneAdapterStorage()._feeds[key];
        if (f.adapter == address(0)) revert IRedStoneAdapter.RedStoneFeedNotRegistered(key);

        value = IRedstonePriceFeedsAdapter(f.adapter).getValueForDataFeed(f.dataFeedId);
        (, uint128 blockTimestamp) = IRedstonePriceFeedsAdapter(f.adapter).getTimestampsFromLatestUpdate();
        timestamp = blockTimestamp;

        if (value == 0) revert IRedStoneAdapter.RedStoneInvalidAnswer(key, value);
        // Future-timestamp guard (avoids an underflow panic and rejects impossible data); treated as stale.
        if (timestamp > block.timestamp || block.timestamp - timestamp > f.maxStaleness) {
            revert IRedStoneAdapter.RedStoneStaleData(key, timestamp, f.maxStaleness);
        }
    }

    /// @notice Returns the latest RedStone value normalized to 18 decimals (WAD): `value * 1e10`.
    /// @dev A value large enough to overflow `int256` after scaling is rejected rather than wrapped.
    function latestAnswer(bytes32 key) internal view returns (int256 answerWad) {
        (uint256 value,) = getValueForDataFeed(key);
        if (value > uint256(type(int256).max) / WAD_SCALE) revert IRedStoneAdapter.RedStoneInvalidAnswer(key, value);
        answerWad = int256(value * WAD_SCALE);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    function registerFeed(bytes32 key, address adapter, bytes32 dataFeedId, uint48 maxStaleness) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (adapter == address(0) || maxStaleness == 0) revert IRedStoneAdapter.RedStoneInvalidConfig();
        redStoneAdapterStorage()._feeds[key] =
            RedStoneFeed({adapter: adapter, maxStaleness: maxStaleness, dataFeedId: dataFeedId});
        emit IRedStoneAdapter.FeedRegistered(key, adapter, dataFeedId, maxStaleness);
    }

    function unregisterFeed(bytes32 key) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        delete redStoneAdapterStorage()._feeds[key];
        emit IRedStoneAdapter.FeedUnregistered(key);
    }
}
