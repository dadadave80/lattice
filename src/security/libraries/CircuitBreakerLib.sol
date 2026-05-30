// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ICircuitBreaker} from "@lattice/interfaces/ICircuitBreaker.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.CircuitBreaker")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant CIRCUIT_BREAKER_STORAGE_SLOT = 0xd8788de4a058793385dd8cf230dd9182ee7825c114e097c68b1e086af1ccbe00;

/// @dev `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant CIRCUIT_BREAKER_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x7462bdca is `type(ICircuitBreaker).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x7462bdca), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ICIRCUITBREAKER_SLOT = 0x9f65a04bbf27ebfd1338d2e0d1c8a9eeb3234866269ee27f320faed8bab02aec;

/// @notice Storage bucket for a single circuit breaker key.
struct CircuitBreakerBucket {
    uint256 threshold;
    uint48 windowSeconds;
    uint48 windowStart;
    uint256 cumulative;
    bool tripped;
}

/// @notice Top-level storage struct for the CircuitBreaker module.
/// @custom:storage-location erc7201:lattice.storage.CircuitBreaker
struct CircuitBreakerStorage {
    mapping(bytes32 key => CircuitBreakerBucket) _buckets;
}

/// @title CircuitBreaker Library
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library implementing a multi-key threshold-based circuit breaker for Diamond facets.
/// @dev Each key tracks an independent cumulative metric within a rolling time window.
///      When the cumulative value meets or exceeds the configured threshold the key trips,
///      blocking any consumer that calls `checkNotTripped`. An admin can reset a tripped key
///      or reconfigure its threshold/window at any time.
library CircuitBreakerLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                          CIRCUIT BREAKER STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the storage struct for CircuitBreaker at its ERC-7201 slot.
    function circuitBreakerStorage() internal pure returns (CircuitBreakerStorage storage $) {
        assembly {
            $.slot := CIRCUIT_BREAKER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the ICircuitBreaker interface via ERC-165.
    /// @dev Writes `true` to the precomputed ERC-165 map slot.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ICIRCUITBREAKER_SLOT, true)
        }
    }

    /// @notice Initializes the CircuitBreaker module.
    /// @dev Must be called between `InitializableLib.preInitializer` and `postInitializer`.
    ///      Registers the ICircuitBreaker interface ID for ERC-165 discovery.
    function __CircuitBreaker_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         CIRCUIT BREAKER OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Configures or updates the threshold and rolling window for `key`.
    /// @dev Requires DEFAULT_ADMIN_ROLE. Resets cumulative and tripped state on reconfiguration.
    ///      Emits `CircuitBreakerThresholdSet`.
    ///      Reverts `CircuitBreakerInvalidThreshold` if `threshold == 0`.
    ///      Reverts `CircuitBreakerInvalidWindow` if `windowSeconds == 0`.
    /// @param key           The circuit breaker key to configure.
    /// @param threshold     The trip threshold value (must be > 0).
    /// @param windowSeconds The rolling window duration in seconds (must be > 0).
    function setThreshold(bytes32 key, uint256 threshold, uint48 windowSeconds) internal {
        AccessControlLib.checkRole(0x00);
        _setThreshold(key, threshold, windowSeconds);
    }

    /// @notice Records an observation for `key`, rolling the window when expired.
    /// @dev Requires DEFAULT_ADMIN_ROLE. Rolls the window if `block.timestamp >= windowStart + windowSeconds`.
    ///      Accumulates `value` and trips the breaker if cumulative >= threshold.
    ///      Reverts `CircuitBreakerNotConfigured` if threshold == 0.
    /// @param key   The circuit breaker key.
    /// @param value The value to add to the current window's cumulative.
    function recordObservation(bytes32 key, uint256 value) internal {
        AccessControlLib.checkRole(0x00);
        _recordObservation(key, value);
    }

    /// @notice Resets the tripped state and cumulative for `key`.
    /// @dev Requires DEFAULT_ADMIN_ROLE. Emits `CircuitBreakerReset`.
    /// @param key The circuit breaker key to reset.
    function reset(bytes32 key) internal {
        AccessControlLib.checkRole(0x00);
        _reset(key);
    }

    /// @notice Reverts with `CircuitBreakerTrippedError` if the circuit breaker for `key` is tripped.
    /// @dev Consumer modules call this to gate protected operations.
    /// @param key The circuit breaker key to check.
    function checkNotTripped(bytes32 key) internal view {
        if (circuitBreakerStorage()._buckets[key].tripped) {
            revert ICircuitBreaker.CircuitBreakerTrippedError(key);
        }
    }

    /// @notice Returns whether the circuit breaker for `key` is currently tripped.
    /// @param key The circuit breaker key to query.
    /// @return bool True if the circuit breaker is tripped, false otherwise.
    function isTripped(bytes32 key) internal view returns (bool) {
        return circuitBreakerStorage()._buckets[key].tripped;
    }

    /// @notice Returns the configured threshold and window for `key`.
    /// @param key The circuit breaker key to query.
    /// @return threshold     The trip threshold (0 means unconfigured).
    /// @return windowSeconds The rolling window duration in seconds.
    function getThreshold(bytes32 key) internal view returns (uint256 threshold, uint48 windowSeconds) {
        CircuitBreakerBucket storage b = circuitBreakerStorage()._buckets[key];
        return (b.threshold, b.windowSeconds);
    }

    /// @notice Returns the current cumulative value and window start time for `key`.
    /// @param key The circuit breaker key to query.
    /// @return cumulative  The accumulated value within the current window.
    /// @return windowStart The timestamp when the current window started.
    function getCumulative(bytes32 key) internal view returns (uint256 cumulative, uint48 windowStart) {
        CircuitBreakerBucket storage b = circuitBreakerStorage()._buckets[key];
        return (b.cumulative, b.windowStart);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Internal — sets threshold + window, resets cumulative and tripped state.
    function _setThreshold(bytes32 key, uint256 threshold, uint48 windowSeconds) internal {
        if (threshold == 0) revert ICircuitBreaker.CircuitBreakerInvalidThreshold();
        if (windowSeconds == 0) revert ICircuitBreaker.CircuitBreakerInvalidWindow();
        CircuitBreakerBucket storage b = circuitBreakerStorage()._buckets[key];
        b.threshold = threshold;
        b.windowSeconds = windowSeconds;
        b.cumulative = 0;
        b.tripped = false;
        b.windowStart = uint48(block.timestamp);
        emit ICircuitBreaker.CircuitBreakerThresholdSet(key, threshold, windowSeconds);
    }

    /// @notice Internal — records observation, rolls window if needed, trips if threshold crossed.
    function _recordObservation(bytes32 key, uint256 value) internal {
        CircuitBreakerBucket storage b = circuitBreakerStorage()._buckets[key];
        if (b.threshold == 0) revert ICircuitBreaker.CircuitBreakerNotConfigured(key);

        // Roll the window if the current window has expired.
        if (block.timestamp >= uint256(b.windowStart) + uint256(b.windowSeconds)) {
            b.cumulative = 0;
            b.windowStart = uint48(block.timestamp);
        }

        b.cumulative += value;

        if (!b.tripped && b.cumulative >= b.threshold) {
            b.tripped = true;
            emit ICircuitBreaker.CircuitBreakerTripped(key, b.cumulative, b.threshold);
        }
    }

    /// @notice Internal — clears tripped flag and cumulative, emits reset event.
    function _reset(bytes32 key) internal {
        CircuitBreakerBucket storage b = circuitBreakerStorage()._buckets[key];
        b.tripped = false;
        b.cumulative = 0;
        emit ICircuitBreaker.CircuitBreakerReset(key);
    }
}
