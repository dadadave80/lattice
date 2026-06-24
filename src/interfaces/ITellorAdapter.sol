// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ITellorAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Tellor (https://github.com/tellor-io)
/// @notice Interface for the TellorAdapter Diamond facet — reads the dispute-based Tellor oracle with
///         per-feed dispute-buffer + staleness configuration and WAD-normalized answers.
/// @dev Tellor is dispute-based and exposes a SINGLE global oracle contract per chain. Reads use
///      `ITellor.getDataBefore(queryId, block.timestamp - disputeBuffer)`, so disputed values have time to
///      be removed before they are consumed. SpotPrice `value` is `abi.encode(uint256)` at 18 decimals
///      (WAD), so normalization only widens `uint256 -> int256`. Feeds are keyed by an arbitrary `bytes32`
///      mapped to a Tellor query id. `latestAnswer(bytes32)->int256` is declared with the same selector as
///      {IPriceOracleReader}, so consumers can read this adapter through that provider-agnostic interface.
///      (Declared directly, not by inheriting {IPriceOracleReader}, because Solidity excludes inherited
///      functions from `type(I).interfaceId`, which would shift the ERC-165 id.)
interface ITellorAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a feed is registered or updated.
    /// @param key The arbitrary feed identifier.
    /// @param queryId The Tellor query id.
    /// @param disputeBuffer Seconds subtracted from `block.timestamp` when reading (dispute window).
    /// @param maxStaleness Maximum age (seconds) before a value is stale.
    event FeedRegistered(bytes32 indexed key, bytes32 indexed queryId, uint48 disputeBuffer, uint48 maxStaleness);

    /// @notice Emitted when a feed is removed.
    /// @param key The removed feed identifier.
    event FeedUnregistered(bytes32 indexed key);

    /// @notice Emitted when the Tellor contract address is set.
    /// @param tellor The Tellor contract.
    event TellorContractSet(address indexed tellor);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice The requested feed key has not been registered.
    error TellorFeedNotRegistered(bytes32 key);

    /// @notice No data was retrieved for the feed (not found, empty, or zero value).
    error TellorNoData(bytes32 key);

    /// @notice The value is older than the feed's `maxStaleness` (or has a future timestamp).
    error TellorStaleData(bytes32 key, uint256 timestamp, uint256 maxStaleness);

    /// @notice `registerFeed` was called with a zero query id or zero `maxStaleness`.
    error TellorInvalidConfig();

    /// @notice The Tellor contract address has not been set.
    error TellorContractNotSet();

    /// @notice Setting the Tellor contract to the zero address.
    error TellorContractIsZero();

    // -------------------------------------------------------------------------
    //                                   Reads
    // -------------------------------------------------------------------------

    /// @notice Returns the Tellor contract address.
    function tellor() external view returns (address);

    /// @notice Returns a feed's configuration.
    /// @param key The feed identifier.
    /// @return queryId The Tellor query id.
    /// @return disputeBuffer Seconds subtracted from `block.timestamp` when reading (dispute window).
    /// @return maxStaleness Maximum age (seconds) before a value is stale.
    function getFeed(bytes32 key) external view returns (bytes32 queryId, uint48 disputeBuffer, uint48 maxStaleness);

    /// @notice Returns the latest price for `key`, normalized to 18 decimals (WAD). Selector matches
    ///         {IPriceOracleReader.latestAnswer}. Reverts on missing / stale / future data.
    /// @param key The feed identifier.
    /// @return answerWad The latest price scaled to 1e18.
    function latestAnswer(bytes32 key) external view returns (int256 answerWad);

    /// @notice Returns the raw Tellor value bytes and report timestamp read with the feed's dispute buffer.
    /// @dev Provider-native reader (mirrors {ITellor.getDataBefore}); keeps this adapter's ERC-165 id
    ///      distinct from other read adapters that share the {latestAnswer} selector.
    /// @param key The feed identifier.
    /// @return value The reported value bytes (SpotPrice is `abi.encode(uint256)` at 18 decimals).
    /// @return timestamp The timestamp the returned value was reported.
    function getDataBefore(bytes32 key) external view returns (bytes memory value, uint256 timestamp);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Sets the Tellor contract. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param tellor_ The Tellor contract (non-zero).
    function setTellor(address tellor_) external;

    /// @notice Registers a Tellor feed under `key`. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param key The arbitrary feed identifier.
    /// @param queryId The Tellor query id (non-zero).
    /// @param disputeBuffer Seconds subtracted from `block.timestamp` when reading (0 = no buffer).
    /// @param maxStaleness Maximum age (seconds); must be non-zero.
    function registerFeed(bytes32 key, bytes32 queryId, uint48 disputeBuffer, uint48 maxStaleness) external;

    /// @notice Removes a registered feed. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param key The feed identifier to remove.
    function unregisterFeed(bytes32 key) external;
}
