// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IDIAAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from DIA (https://github.com/diadata-org)
/// @notice Interface for the DIAAdapter Diamond facet — reads DIA OracleV2 price feeds through their
///         string-keyed `getValue` API and exposes WAD-normalized answers.
/// @dev DIA values are read via `IDIAOracleV2.getValue(string) -> (uint128 value, uint128 timestamp)`;
///      `value` has 8 decimals and is normalized to 18 decimals (WAD) by multiplying by 1e10. Feeds are
///      keyed by an arbitrary `bytes32` mapped to an oracle address + DIA key string. `latestAnswer(bytes32)->int256`
///      is declared with the same selector as {IPriceOracleReader}, so consumers can read this adapter through
///      that provider-agnostic interface. (Declared directly, not by inheriting {IPriceOracleReader},
///      because Solidity excludes inherited functions from `type(I).interfaceId`, which would shift the
///      ERC-165 id.) The native `getValue(bytes32)` reader keeps this adapter's ERC-165 id distinct from
///      other adapters that share the `latestAnswer` selector.
interface IDIAAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a feed is registered or updated.
    /// @param key The arbitrary feed identifier.
    /// @param oracle The DIA OracleV2 contract address.
    /// @param diaKey The DIA price key string (e.g. "ETH/USD").
    /// @param maxStaleness Maximum age (seconds) before a value is stale.
    event FeedRegistered(bytes32 indexed key, address indexed oracle, string diaKey, uint48 maxStaleness);

    /// @notice Emitted when a feed is removed.
    /// @param key The removed feed identifier.
    event FeedUnregistered(bytes32 indexed key);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice The requested feed key has not been registered.
    error DIAFeedNotRegistered(bytes32 key);

    /// @notice The value is older than the feed's `maxStaleness` (or has a future timestamp).
    error DIAStaleData(bytes32 key, uint256 timestamp, uint256 maxStaleness);

    /// @notice The oracle returned a zero value.
    error DIAInvalidAnswer(bytes32 key, uint128 value);

    /// @notice `registerFeed` was called with a zero oracle address, empty key string, or zero `maxStaleness`.
    error DIAInvalidConfig();

    // -------------------------------------------------------------------------
    //                                   Reads
    // -------------------------------------------------------------------------

    /// @notice Returns a feed's configuration.
    /// @param key The feed identifier.
    /// @return oracle The DIA OracleV2 contract address.
    /// @return diaKey The DIA price key string.
    /// @return maxStaleness Maximum age (seconds) before a value is stale.
    function getFeed(bytes32 key) external view returns (address oracle, string memory diaKey, uint48 maxStaleness);

    /// @notice Returns the latest price for `key`, normalized to 18 decimals (WAD). Selector matches
    ///         {IPriceOracleReader.latestAnswer}. Reverts on stale / future / zero value.
    /// @param key The feed identifier.
    /// @return answerWad The latest price scaled to 1e18.
    function latestAnswer(bytes32 key) external view returns (int256 answerWad);

    /// @notice Returns the validated raw DIA value and its update timestamp, in DIA's native types.
    /// @dev Provider-native reader (mirrors {IDIAOracleV2.getValue}); keeps this adapter's ERC-165 id
    ///      distinct from other read adapters that share the {latestAnswer} selector.
    /// @param key The feed identifier.
    /// @return value The DIA value (8 decimals).
    /// @return timestamp The off-chain update timestamp.
    function getValue(bytes32 key) external view returns (uint128 value, uint128 timestamp);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Registers a DIA feed under `key`. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param key The arbitrary feed identifier.
    /// @param oracle The DIA OracleV2 contract address (non-zero).
    /// @param diaKey The DIA price key string (non-empty).
    /// @param maxStaleness Maximum age (seconds); must be non-zero.
    function registerFeed(bytes32 key, address oracle, string calldata diaKey, uint48 maxStaleness) external;

    /// @notice Removes a registered feed. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param key The feed identifier to remove.
    function unregisterFeed(bytes32 key) external;
}
