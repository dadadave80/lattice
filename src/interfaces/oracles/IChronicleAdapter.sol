// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IChronicleAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Chronicle (https://github.com/chronicleprotocol)
/// @notice Interface for the ChronicleAdapter Diamond facet — reads Chronicle oracle feeds through their
///         per-feed oracle contract and exposes WAD-normalized answers.
/// @dev Chronicle values are already 18-decimals (WAD), so normalization only casts `uint256 -> int256`
///      (no rescaling). Feeds are keyed by an arbitrary `bytes32` mapped to a Chronicle oracle address.
///      `latestAnswer(bytes32)->int256` is declared with the same selector as {IPriceOracleReader}, so
///      consumers can read this adapter through that provider-agnostic interface. (Declared directly, not
///      by inheriting {IPriceOracleReader}, because Solidity excludes inherited functions from
///      `type(I).interfaceId`, which would shift the ERC-165 id.)
///
///      OPERATIONAL PREREQUISITE — toll-gating: Chronicle oracles are Schnorr-signed and access-controlled.
///      The adapter contract address must be whitelisted ("`kiss`ed") by the oracle operator before any
///      `read()` or `readWithAge()` call will succeed. Without whitelisting, calls will revert at the
///      Chronicle contract. Contact the Chronicle team or use the self-service portal to request access.
interface IChronicleAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a feed is registered or updated.
    /// @param key          The arbitrary feed identifier.
    /// @param chronicle    The Chronicle oracle contract address.
    /// @param maxStaleness Maximum age (seconds) before a value is stale.
    event FeedRegistered(bytes32 indexed key, address indexed chronicle, uint48 maxStaleness);

    /// @notice Emitted when a feed is removed.
    /// @param key The removed feed identifier.
    event FeedUnregistered(bytes32 indexed key);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice The requested feed key has not been registered.
    error ChronicleFeedNotRegistered(bytes32 key);

    /// @notice The value is older than the feed's `maxStaleness` (or has a future `age` timestamp).
    error ChronicleStaleData(bytes32 key, uint256 age, uint256 maxStaleness);

    /// @notice The oracle returned a zero value.
    error ChronicleInvalidAnswer(bytes32 key, uint256 value);

    /// @notice `registerFeed` was called with a zero chronicle address or zero `maxStaleness`.
    error ChronicleInvalidConfig();

    // -------------------------------------------------------------------------
    //                                   Reads
    // -------------------------------------------------------------------------

    /// @notice Returns a feed's configuration.
    /// @param key The feed identifier.
    /// @return chronicle    The Chronicle oracle contract address.
    /// @return maxStaleness Maximum age (seconds) before a value is stale.
    function getFeed(bytes32 key) external view returns (address chronicle, uint48 maxStaleness);

    /// @notice Returns the latest price for `key`, normalized to 18 decimals (WAD). Selector matches
    ///         {IPriceOracleReader.latestAnswer}. Reverts on stale / future-age / zero value.
    /// @param key The feed identifier.
    /// @return answerWad The latest price scaled to 1e18.
    function latestAnswer(bytes32 key) external view returns (int256 answerWad);

    /// @notice Returns the validated raw Chronicle value and the timestamp it was last written on-chain.
    /// @dev Provider-native reader (mirrors {IChronicle.readWithAge}); keeps this adapter's ERC-165 id
    ///      distinct from other adapters that share the {latestAnswer} selector.
    /// @param key The feed identifier.
    /// @return value The oracle value (already 18 decimals, WAD).
    /// @return age   The Unix timestamp at which the value was last written on-chain.
    function readWithAge(bytes32 key) external view returns (uint256 value, uint256 age);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Registers a Chronicle feed under `key`. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param key          The arbitrary feed identifier.
    /// @param chronicle    The Chronicle oracle contract address (non-zero).
    /// @param maxStaleness Maximum age (seconds); must be non-zero.
    function registerFeed(bytes32 key, address chronicle, uint48 maxStaleness) external;

    /// @notice Removes a registered feed. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param key The feed identifier to remove.
    function unregisterFeed(bytes32 key) external;
}
