// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IRedStoneAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from RedStone (https://github.com/redstone-finance/redstone-oracles-monorepo)
/// @notice Interface for the RedStoneAdapter Diamond facet — reads RedStone Push price feeds from their
///         on-chain `PriceFeedsAdapter` with per-feed staleness configuration and WAD-normalized answers.
/// @dev This adapter targets the RedStone **Push** model: signed values are relayed on-chain and read via
///      {IRedstonePriceFeedsAdapter.getValueForDataFeed} (8 decimals) with the batch update time from
///      `getTimestampsFromLatestUpdate`. (The RedStone **Core**/pull model, which extracts signed data from
///      calldata via the RedStone SDK, is a separate follow-up.) Feeds are keyed by an arbitrary `bytes32`
///      mapped to a `(PriceFeedsAdapter, dataFeedId)` pair. `latestAnswer(bytes32)->int256` is declared
///      with the same selector as {IPriceOracleReader}, so consumers can read this adapter through that
///      provider-agnostic interface. (Declared directly, not by inheriting {IPriceOracleReader}, because
///      Solidity excludes inherited functions from `type(I).interfaceId`, which would shift the ERC-165
///      id.)
interface IRedStoneAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a feed is registered or updated.
    /// @param key The arbitrary feed identifier.
    /// @param adapter The RedStone PriceFeedsAdapter contract.
    /// @param dataFeedId The RedStone data-feed id.
    /// @param maxStaleness Maximum age (seconds) before a value is stale.
    event FeedRegistered(bytes32 indexed key, address indexed adapter, bytes32 indexed dataFeedId, uint48 maxStaleness);

    /// @notice Emitted when a feed is removed.
    /// @param key The removed feed identifier.
    event FeedUnregistered(bytes32 indexed key);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice The requested feed key has not been registered.
    error RedStoneFeedNotRegistered(bytes32 key);

    /// @notice The value is older than the feed's `maxStaleness` (or has a future timestamp).
    error RedStoneStaleData(bytes32 key, uint256 timestamp, uint256 maxStaleness);

    /// @notice The adapter returned a zero value, or one too large to normalize without overflow.
    error RedStoneInvalidAnswer(bytes32 key, uint256 value);

    /// @notice `registerFeed` was called with a zero adapter address or zero `maxStaleness`.
    error RedStoneInvalidConfig();

    // -------------------------------------------------------------------------
    //                                   Reads
    // -------------------------------------------------------------------------

    /// @notice Returns a feed's configuration.
    /// @param key The feed identifier.
    /// @return adapter The RedStone PriceFeedsAdapter contract.
    /// @return dataFeedId The RedStone data-feed id.
    /// @return maxStaleness Maximum age (seconds) before a value is stale.
    function getFeed(bytes32 key) external view returns (address adapter, bytes32 dataFeedId, uint48 maxStaleness);

    /// @notice Returns the latest price for `key`, normalized to 18 decimals (WAD). Selector matches
    ///         {IPriceOracleReader.latestAnswer}. Reverts on stale / future / zero / overflowing value.
    /// @param key The feed identifier.
    /// @return answerWad The latest price scaled to 1e18.
    function latestAnswer(bytes32 key) external view returns (int256 answerWad);

    /// @notice Returns the validated raw RedStone value (8 decimals) and the batch update timestamp.
    /// @dev Provider-native reader; keeps this adapter's ERC-165 id distinct from other read adapters that
    ///      share the {latestAnswer} selector.
    /// @param key The feed identifier.
    /// @return value The RedStone value (8 decimals).
    /// @return timestamp The on-chain batch update timestamp (seconds).
    function getValueForDataFeed(bytes32 key) external view returns (uint256 value, uint256 timestamp);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Registers a RedStone feed under `key`. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param key The arbitrary feed identifier.
    /// @param adapter The RedStone PriceFeedsAdapter contract (non-zero).
    /// @param dataFeedId The RedStone data-feed id.
    /// @param maxStaleness Maximum age (seconds); must be non-zero.
    function registerFeed(bytes32 key, address adapter, bytes32 dataFeedId, uint48 maxStaleness) external;

    /// @notice Removes a registered feed. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param key The feed identifier to remove.
    function unregisterFeed(bytes32 key) external;
}
