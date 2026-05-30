// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IChainlinkAdapter
/// @notice Interface for the ChainlinkAdapter Diamond facet.
/// @dev Price feeds are identified by an arbitrary `bytes32` key chosen by the
///      administrator.  All answers returned by `latestAnswer` are normalised to
///      18 decimal places (WAD).
interface IChainlinkAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a price feed is registered or updated.
    /// @param key          Arbitrary identifier for this feed.
    /// @param feed         Address of the AggregatorV3 contract.
    /// @param maxStaleness Maximum age (seconds) before an answer is considered stale.
    event FeedRegistered(bytes32 indexed key, address feed, uint48 maxStaleness);

    /// @notice Emitted when a price feed is removed.
    /// @param key The identifier of the removed feed.
    event FeedUnregistered(bytes32 indexed key);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice The requested feed key has not been registered.
    error ChainlinkFeedNotRegistered(bytes32 key);

    /// @notice The latest round data is older than `maxStaleness`.
    /// @param key          The feed identifier.
    /// @param updatedAt    The `updatedAt` timestamp returned by the feed.
    /// @param maxStaleness The configured maximum staleness for this feed.
    error ChainlinkStaleData(bytes32 key, uint256 updatedAt, uint256 maxStaleness);

    /// @notice The feed returned a non-positive answer.
    /// @param key    The feed identifier.
    /// @param answer The invalid answer value.
    error ChainlinkInvalidAnswer(bytes32 key, int256 answer);

    /// @notice The round has not been completed (`answeredInRound < roundId` or `updatedAt == 0`).
    /// @param key The feed identifier.
    error ChainlinkRoundIncomplete(bytes32 key);

    // -------------------------------------------------------------------------
    //                                   Reads
    // -------------------------------------------------------------------------

    /// @notice Returns the registered feed address and staleness threshold for a key.
    /// @param key The feed identifier.
    /// @return feed         Address of the AggregatorV3 feed.
    /// @return maxStaleness Maximum age in seconds before data is considered stale.
    function getFeed(bytes32 key) external view returns (address feed, uint48 maxStaleness);

    /// @notice Returns the latest price normalised to 18 decimal places.
    /// @param key The feed identifier.
    /// @return answerWad The latest price scaled to 1e18.
    function latestAnswer(bytes32 key) external view returns (int256 answerWad);

    /// @notice Returns the raw latest price, its update timestamp, and the feed's decimals.
    /// @param key The feed identifier.
    /// @return answer    The raw answer from the feed.
    /// @return updatedAt The timestamp of the last update.
    /// @return decimals_ The number of decimals used by the feed.
    function latestAnswerRaw(bytes32 key) external view returns (int256 answer, uint256 updatedAt, uint8 decimals_);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Registers a Chainlink price feed under the given key.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`.  The feed's `decimals()` is
    ///      read and cached at registration time.
    /// @param key          Arbitrary identifier for this feed.
    /// @param feed         Address of the AggregatorV3 contract.
    /// @param maxStaleness Maximum age (seconds) an answer may be before it is
    ///                     considered stale.  Must be non-zero.
    function registerFeed(bytes32 key, address feed, uint48 maxStaleness) external;

    /// @notice Removes a registered price feed.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param key The feed identifier to remove.
    function unregisterFeed(bytes32 key) external;
}
