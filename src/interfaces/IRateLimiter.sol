// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IRateLimiter
/// @notice Interface for the RateLimiter module — a token-bucket rate limiter keyed by `bytes32`.
///         Each key has a `capacity` (max bucket size) and `refillRate` (tokens per second).
interface IRateLimiter {
    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @dev Emitted when a rate limit bucket is configured or updated.
    /// @param key        The rate limit key.
    /// @param capacity   The maximum number of tokens in the bucket.
    /// @param refillRate The number of tokens added per second.
    event RateLimitConfigured(bytes32 indexed key, uint256 capacity, uint256 refillRate);

    /// @dev Emitted when tokens are successfully consumed from a bucket.
    /// @param key       The rate limit key.
    /// @param consumer  The address that consumed the tokens.
    /// @param amount    The number of tokens consumed.
    /// @param remaining The number of tokens remaining in the bucket after consumption.
    event RateLimitConsumed(bytes32 indexed key, address indexed consumer, uint256 amount, uint256 remaining);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @dev Thrown when an operation is attempted on a key that has not been configured.
    /// @param key The unconfigured rate limit key.
    error RateLimitNotConfigured(bytes32 key);

    /// @dev Thrown when a consume request exceeds the currently available tokens.
    /// @param key       The rate limit key.
    /// @param requested The number of tokens requested.
    /// @param available The number of tokens currently available.
    error RateLimitExceeded(bytes32 key, uint256 requested, uint256 available);

    /// @dev Thrown when `configure` is called with a zero capacity or zero refill rate.
    error RateLimitInvalidConfig();

    /// @dev Thrown when `consume` is called with `amount == 0`.
    error RateLimitInvalidAmount();

    // -------------------------------------------------------------------------
    // View functions
    // -------------------------------------------------------------------------

    /// @notice Returns the capacity and refill rate configured for `key`.
    /// @param key The rate limit key to query.
    /// @return capacity   The maximum token capacity of the bucket.
    /// @return refillRate The number of tokens refilled per second.
    function getConfig(bytes32 key) external view returns (uint256 capacity, uint256 refillRate);

    /// @notice Returns the currently available tokens for `key` (accounts for elapsed time).
    /// @dev This is a pure read — it does NOT update storage.
    /// @param key The rate limit key to query.
    /// @return available The number of tokens available right now.
    function getAvailable(bytes32 key) external view returns (uint256 available);

    // -------------------------------------------------------------------------
    // State-changing functions
    // -------------------------------------------------------------------------

    /// @notice Configures or reconfigures a rate limit bucket.
    /// @dev Requires DEFAULT_ADMIN_ROLE. Sets `tokens = capacity` and `lastRefill = now`.
    ///      Reverts with `RateLimitInvalidConfig` if `capacity == 0` OR `refillRate == 0`.
    ///      Emits `RateLimitConfigured`.
    /// @param key        The rate limit key.
    /// @param capacity   The maximum token capacity (must be > 0).
    /// @param refillRate The tokens-per-second refill rate (must be > 0).
    function configure(bytes32 key, uint256 capacity, uint256 refillRate) external;

    /// @notice Consumes `amount` tokens from the bucket for `key`.
    /// @dev Refills the bucket first based on elapsed time, then deducts `amount`.
    ///      Reverts with `RateLimitInvalidAmount` if `amount == 0`.
    ///      Reverts with `RateLimitNotConfigured` if the key has no configuration.
    ///      Reverts with `RateLimitExceeded` if fewer than `amount` tokens are available.
    ///      Emits `RateLimitConsumed`.
    /// @param key    The rate limit key.
    /// @param amount The number of tokens to consume (must be > 0).
    function consume(bytes32 key, uint256 amount) external;
}
