// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ICircuitBreaker
/// @notice Interface for the CircuitBreaker module — a multi-key threshold-based pause that
///         automatically trips when a tracked metric exceeds a threshold within a rolling window.
interface ICircuitBreaker {
    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @dev Emitted when a circuit breaker is tripped because the cumulative value crossed the threshold.
    /// @param key     The circuit breaker key.
    /// @param value   The cumulative value at the time of tripping.
    /// @param threshold The configured threshold that was exceeded.
    event CircuitBreakerTripped(bytes32 indexed key, uint256 value, uint256 threshold);

    /// @dev Emitted when an admin resets a tripped circuit breaker.
    /// @param key The circuit breaker key that was reset.
    event CircuitBreakerReset(bytes32 indexed key);

    /// @dev Emitted when the threshold and window for a key are configured or updated.
    /// @param key           The circuit breaker key.
    /// @param threshold     The new threshold value.
    /// @param windowSeconds The new rolling window duration in seconds.
    event CircuitBreakerThresholdSet(bytes32 indexed key, uint256 threshold, uint48 windowSeconds);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @dev Thrown when an operation is attempted on a key that has not been configured yet.
    /// @param key The unconfigured circuit breaker key.
    error CircuitBreakerNotConfigured(bytes32 key);

    /// @dev Thrown when an operation is blocked because the circuit breaker is tripped.
    /// @param key The tripped circuit breaker key.
    error CircuitBreakerTrippedError(bytes32 key);

    /// @dev Thrown when `windowSeconds == 0` is passed to `setThreshold`.
    error CircuitBreakerInvalidWindow();

    /// @dev Thrown when `threshold == 0` is passed to `setThreshold`.
    error CircuitBreakerInvalidThreshold();

    // -------------------------------------------------------------------------
    // View functions
    // -------------------------------------------------------------------------

    /// @notice Returns whether the circuit breaker for `key` is currently tripped.
    /// @param key The circuit breaker key to query.
    /// @return bool True if the circuit breaker is tripped, false otherwise.
    function isTripped(bytes32 key) external view returns (bool);

    /// @notice Returns the configured threshold and window for `key`.
    /// @param key The circuit breaker key to query.
    /// @return threshold     The trip threshold (0 means unconfigured).
    /// @return windowSeconds The rolling window duration in seconds.
    function getThreshold(bytes32 key) external view returns (uint256 threshold, uint48 windowSeconds);

    /// @notice Returns the current cumulative value and window start time for `key`.
    /// @param key The circuit breaker key to query.
    /// @return cumulative   The accumulated value within the current window.
    /// @return windowStart  The timestamp when the current window started.
    function getCumulative(bytes32 key) external view returns (uint256 cumulative, uint48 windowStart);

    // -------------------------------------------------------------------------
    // State-changing functions
    // -------------------------------------------------------------------------

    /// @notice Configures or updates the threshold and rolling window for `key`.
    /// @dev Requires DEFAULT_ADMIN_ROLE. Resets cumulative and tripped state.
    ///      Reverts with `CircuitBreakerInvalidThreshold` if `threshold == 0`.
    ///      Reverts with `CircuitBreakerInvalidWindow` if `windowSeconds == 0`.
    /// @param key           The circuit breaker key to configure.
    /// @param threshold     The trip threshold value (must be > 0).
    /// @param windowSeconds The rolling window duration in seconds (must be > 0).
    function setThreshold(bytes32 key, uint256 threshold, uint48 windowSeconds) external;

    /// @notice Records an observation for `key`, rolling the window if necessary.
    /// @dev Requires DEFAULT_ADMIN_ROLE. If `block.timestamp >= windowStart + windowSeconds`,
    ///      the window resets before accumulating. If the new cumulative value meets or exceeds
    ///      the threshold the circuit trips and emits `CircuitBreakerTripped`.
    ///      Reverts with `CircuitBreakerNotConfigured` if the key has not been set up.
    /// @param key   The circuit breaker key.
    /// @param value The value to add to the current window's cumulative.
    function recordObservation(bytes32 key, uint256 value) external;

    /// @notice Resets the tripped state and cumulative for `key`.
    /// @dev Requires DEFAULT_ADMIN_ROLE. Emits `CircuitBreakerReset`.
    /// @param key The circuit breaker key to reset.
    function reset(bytes32 key) external;
}
