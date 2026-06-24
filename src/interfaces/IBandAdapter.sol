// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IBandAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Band Protocol (https://github.com/bandprotocol)
/// @notice Interface for the BandAdapter Diamond facet — reads Band Protocol reference data through the
///         single global StdReference contract with per-feed staleness configuration and WAD-normalized
///         answers.
/// @dev Band uses ONE global StdReference contract per chain; feeds are keyed by an arbitrary `bytes32`
///      mapped to a `(base, quote)` symbol pair. `rate` is already 18-decimals (WAD), so normalization
///      only widens `uint256 -> int256` (no rescaling); reads validate registration, sign, future
///      timestamp, and staleness on-chain. `latestAnswer(bytes32)->int256` is declared with the same
///      selector as {IPriceOracleReader}, so consumers can read this adapter through that
///      provider-agnostic interface. (Declared directly, not by inheriting {IPriceOracleReader}, because
///      Solidity excludes inherited functions from `type(I).interfaceId`, which would shift the ERC-165
///      id.)
interface IBandAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a feed is registered or updated.
    /// @param key The arbitrary feed identifier.
    /// @param base The base symbol (e.g. `"ETH"`).
    /// @param quote The quote symbol (e.g. `"USD"`).
    /// @param maxStaleness Maximum age (seconds) before a value is stale.
    event FeedRegistered(bytes32 indexed key, string base, string quote, uint48 maxStaleness);

    /// @notice Emitted when a feed is removed.
    /// @param key The removed feed identifier.
    event FeedUnregistered(bytes32 indexed key);

    /// @notice Emitted when the StdReference contract address is set.
    /// @param stdReference The StdReference contract.
    event ReferenceSet(address indexed stdReference);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice The requested feed key has not been registered.
    error BandFeedNotRegistered(bytes32 key);

    /// @notice The rate is older than the feed's `maxStaleness` (or has a future timestamp).
    error BandStaleData(bytes32 key, uint256 lastUpdated, uint256 maxStaleness);

    /// @notice The reference returned a zero rate.
    error BandInvalidAnswer(bytes32 key, uint256 rate);

    /// @notice `registerFeed` was called with an empty `base`/`quote` symbol or zero `maxStaleness`.
    error BandInvalidConfig();

    /// @notice The StdReference contract address has not been set.
    error BandReferenceNotSet();

    /// @notice Setting the StdReference contract to the zero address.
    error BandReferenceIsZero();

    // -------------------------------------------------------------------------
    //                                   Reads
    // -------------------------------------------------------------------------

    /// @notice Returns the StdReference contract address.
    function stdReference() external view returns (address);

    /// @notice Returns a feed's configuration.
    /// @param key The feed identifier.
    /// @return base The base symbol (e.g. `"ETH"`).
    /// @return quote The quote symbol (e.g. `"USD"`).
    /// @return maxStaleness Maximum age (seconds) before a value is stale.
    function getFeed(bytes32 key) external view returns (string memory base, string memory quote, uint48 maxStaleness);

    /// @notice Returns the latest rate for `key`, normalized to 18 decimals (WAD). Selector matches
    ///         {IPriceOracleReader.latestAnswer}. Reverts on stale / future / zero rate.
    /// @param key The feed identifier.
    /// @return answerWad The latest rate scaled to 1e18.
    function latestAnswer(bytes32 key) external view returns (int256 answerWad);

    /// @notice Returns the validated raw Band reference data for `key`, in Band's native types.
    /// @dev Provider-native reader (mirrors {IStdReference.getReferenceData}); keeps this adapter's
    ///      ERC-165 id distinct from other read adapters that share the {latestAnswer} selector.
    /// @param key The feed identifier.
    /// @return rate The base/quote exchange rate (already 18 decimals).
    /// @return lastUpdatedBase The unix timestamp the base symbol was last updated.
    /// @return lastUpdatedQuote The unix timestamp the quote symbol was last updated.
    function getReferenceData(bytes32 key)
        external
        view
        returns (uint256 rate, uint256 lastUpdatedBase, uint256 lastUpdatedQuote);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Sets the StdReference contract. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param reference_ The StdReference contract (non-zero).
    function setReference(address reference_) external;

    /// @notice Registers a Band feed under `key`. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param key The arbitrary feed identifier.
    /// @param base The base symbol (non-empty, e.g. `"ETH"`).
    /// @param quote The quote symbol (non-empty, e.g. `"USD"`).
    /// @param maxStaleness Maximum age (seconds); must be non-zero.
    function registerFeed(bytes32 key, string calldata base, string calldata quote, uint48 maxStaleness) external;

    /// @notice Removes a registered feed. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param key The feed identifier to remove.
    function unregisterFeed(bytes32 key) external;
}
