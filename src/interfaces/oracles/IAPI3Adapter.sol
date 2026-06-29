// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAPI3Adapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from API3 (https://github.com/api3dao/contracts)
/// @notice Interface for the API3Adapter Diamond facet — reads API3 dAPIs through their per-feed
///         reader proxy and exposes WAD-normalized answers.
/// @dev dAPIs are read via `IApi3Proxy.read() -> (int224 value, uint32 timestamp)`; `value` is already
///      18-decimals (WAD), so normalization only widens `int224 -> int256` (no rescaling). Feeds are keyed
///      by an arbitrary `bytes32` mapped to a dAPI proxy address. `latestAnswer(bytes32)->int256` is
///      declared with the same selector as {IPriceOracleReader}, so consumers can read this adapter through
///      that provider-agnostic interface. (Declared directly, not by inheriting {IPriceOracleReader},
///      because Solidity excludes inherited functions from `type(I).interfaceId`, which would shift the
///      ERC-165 id.)
interface IAPI3Adapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a feed is registered or updated.
    /// @param key The arbitrary feed identifier.
    /// @param proxy The dAPI reader proxy address.
    /// @param maxStaleness Maximum age (seconds) before a value is stale.
    event FeedRegistered(bytes32 indexed key, address indexed proxy, uint48 maxStaleness);

    /// @notice Emitted when a feed is removed.
    /// @param key The removed feed identifier.
    event FeedUnregistered(bytes32 indexed key);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice The requested feed key has not been registered.
    error API3FeedNotRegistered(bytes32 key);

    /// @notice The value is older than the feed's `maxStaleness` (or has a future timestamp).
    error API3StaleData(bytes32 key, uint256 timestamp, uint256 maxStaleness);

    /// @notice The proxy returned a non-positive value.
    error API3InvalidAnswer(bytes32 key, int256 value);

    /// @notice `registerFeed` was called with a zero proxy address or zero `maxStaleness`.
    error API3InvalidConfig();

    // -------------------------------------------------------------------------
    //                                   Reads
    // -------------------------------------------------------------------------

    /// @notice Returns a feed's configuration.
    /// @param key The feed identifier.
    /// @return proxy The dAPI reader proxy address.
    /// @return maxStaleness Maximum age (seconds) before a value is stale.
    function getFeed(bytes32 key) external view returns (address proxy, uint48 maxStaleness);

    /// @notice Returns the latest price for `key`, normalized to 18 decimals (WAD). Selector matches
    ///         {IPriceOracleReader.latestAnswer}. Reverts on stale / future / non-positive value.
    /// @param key The feed identifier.
    /// @return answerWad The latest price scaled to 1e18.
    function latestAnswer(bytes32 key) external view returns (int256 answerWad);

    /// @notice Returns the validated raw dAPI value and its update timestamp, in API3's native types.
    /// @dev Provider-native reader (mirrors {IApi3Proxy.read}); keeps this adapter's ERC-165 id distinct
    ///      from other read adapters that share the {latestAnswer} selector.
    /// @param key The feed identifier.
    /// @return value The dAPI value (already 18 decimals).
    /// @return timestamp The off-chain update timestamp.
    function read(bytes32 key) external view returns (int224 value, uint32 timestamp);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Registers a dAPI feed under `key`. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param key The arbitrary feed identifier.
    /// @param proxy The dAPI reader proxy address (non-zero).
    /// @param maxStaleness Maximum age (seconds); must be non-zero.
    function registerFeed(bytes32 key, address proxy, uint48 maxStaleness) external;

    /// @notice Removes a registered feed. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param key The feed identifier to remove.
    function unregisterFeed(bytes32 key) external;
}
