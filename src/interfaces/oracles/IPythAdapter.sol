// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IPythAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Pyth Network (https://github.com/pyth-network/pyth-crosschain)
/// @notice Interface for the PythAdapter Diamond facet — Pyth price feeds with per-feed staleness +
///         confidence configuration and WAD-normalized answers.
/// @dev Pyth is PULL-based: prices are refreshed by submitting signed `updateData` (paying a fee) via the
///      payable {updatePriceFeeds}, then read via {latestAnswer}/{latestAnswerRaw} (which validate
///      staleness, future timestamps, sign, and confidence). Feeds are keyed by an arbitrary `bytes32`
///      mapped to a Pyth price-feed id. `latestAnswer(bytes32)->int256` is declared with the same
///      selector as {IPriceOracleReader}, so consumers can read this adapter through that
///      provider-agnostic interface. (Declared directly, not by inheriting {IPriceOracleReader}, because
///      Solidity excludes inherited functions from `type(I).interfaceId`, which would shift the ERC-165
///      id.)
interface IPythAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a feed is registered or updated.
    /// @param key The arbitrary feed identifier.
    /// @param priceId The Pyth price-feed id.
    /// @param maxStaleness Maximum age (seconds) before a price is stale.
    /// @param maxConfBps Maximum confidence ratio in basis points (`conf/price`); 0 disables the check.
    event FeedRegistered(bytes32 indexed key, bytes32 indexed priceId, uint48 maxStaleness, uint64 maxConfBps);

    /// @notice Emitted when a feed is removed.
    /// @param key The removed feed identifier.
    event FeedUnregistered(bytes32 indexed key);

    /// @notice Emitted when the Pyth contract address is set.
    /// @param pyth The Pyth contract.
    event PythContractSet(address indexed pyth);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice The requested feed key has not been registered.
    error PythFeedNotRegistered(bytes32 key);

    /// @notice The price is older than the feed's `maxStaleness`.
    error PythStaleData(bytes32 key, uint256 publishTime, uint256 maxStaleness);

    /// @notice The price has a future publish time.
    error PythFuturePrice(bytes32 key, uint256 publishTime);

    /// @notice The feed returned a non-positive price.
    error PythInvalidAnswer(bytes32 key, int64 price);

    /// @notice The confidence ratio `conf/price` exceeds the feed's `maxConfBps`.
    error PythConfidenceTooWide(bytes32 key, uint64 conf, int64 price, uint64 maxConfBps);

    /// @notice The price exponent is outside the supported normalization range.
    error PythExpoOutOfRange(int32 expo);

    /// @notice `registerFeed` was called with a zero price id or zero `maxStaleness`.
    error PythInvalidConfig();

    /// @notice The Pyth contract address has not been set.
    error PythContractNotSet();

    /// @notice Setting the Pyth contract to the zero address.
    error PythContractIsZero();

    /// @notice `msg.value` is less than the required Pyth update fee.
    error PythInsufficientFee(uint256 provided, uint256 required);

    /// @notice The excess-fee refund to the caller failed.
    error PythRefundFailed();

    // -------------------------------------------------------------------------
    //                                   Reads
    // -------------------------------------------------------------------------

    /// @notice Returns the Pyth contract address.
    function pyth() external view returns (address);

    /// @notice Returns a feed's configuration.
    /// @param key The feed identifier.
    /// @return priceId The Pyth price-feed id.
    /// @return maxStaleness Maximum age (seconds) before a price is stale.
    /// @return maxConfBps Maximum confidence ratio in basis points (0 = disabled).
    function getFeed(bytes32 key) external view returns (bytes32 priceId, uint48 maxStaleness, uint64 maxConfBps);

    /// @notice Returns the latest price for `key`, normalized to 18 decimals (WAD). Selector matches
    ///         {IPriceOracleReader.latestAnswer}. Reverts on stale / future / non-positive / wide-confidence.
    /// @param key The feed identifier.
    /// @return answerWad The latest price scaled to 1e18.
    function latestAnswer(bytes32 key) external view returns (int256 answerWad);

    /// @notice Returns the validated raw price for `key`.
    /// @param key The feed identifier.
    /// @return price The Pyth price (scale `10^expo`).
    /// @return expo The price exponent.
    /// @return conf The confidence interval.
    /// @return publishTime The publish timestamp.
    function latestAnswerRaw(bytes32 key)
        external
        view
        returns (int64 price, int32 expo, uint64 conf, uint256 publishTime);

    /// @notice Returns the fee (wei) required to submit `updateData`.
    /// @param updateData The signed Pyth price-update blobs.
    function getUpdateFee(bytes[] calldata updateData) external view returns (uint256 feeAmount);

    // -------------------------------------------------------------------------
    //                                  Updates
    // -------------------------------------------------------------------------

    /// @notice Refreshes on-chain Pyth prices from `updateData`. Permissionless and caller-funded:
    ///         `msg.value` must be `>= getUpdateFee(updateData)`; any excess is refunded to the caller.
    /// @param updateData The signed Pyth price-update blobs.
    function updatePriceFeeds(bytes[] calldata updateData) external payable;

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Sets the Pyth contract. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param pyth_ The Pyth contract (non-zero).
    function setPyth(address pyth_) external;

    /// @notice Registers a Pyth feed under `key`. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param key The arbitrary feed identifier.
    /// @param priceId The Pyth price-feed id (non-zero).
    /// @param maxStaleness Maximum age (seconds); must be non-zero.
    /// @param maxConfBps Maximum confidence ratio in basis points (0 = disabled).
    function registerFeed(bytes32 key, bytes32 priceId, uint48 maxStaleness, uint64 maxConfBps) external;

    /// @notice Removes a registered feed. Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param key The feed identifier to remove.
    function unregisterFeed(bytes32 key) external;
}
