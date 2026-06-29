// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ICircuitBreaker} from "@lattice/interfaces/security/ICircuitBreaker.sol";
import {CircuitBreakerLib} from "@lattice/security/libraries/CircuitBreakerLib.sol";

/// @title CircuitBreaker
/// @notice Thin Diamond facet that exposes multi-key threshold-based circuit breaking.
/// @dev All logic lives in {CircuitBreakerLib}. This contract is stateless and forwards
///      every call to the library. Inherit this in your Diamond facet to add circuit-breaking.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract CircuitBreaker is ICircuitBreaker {
    /// @inheritdoc ICircuitBreaker
    function isTripped(bytes32 key) public view virtual returns (bool) {
        return CircuitBreakerLib.isTripped(key);
    }

    /// @inheritdoc ICircuitBreaker
    function getThreshold(bytes32 key) public view virtual returns (uint256 threshold, uint48 windowSeconds) {
        return CircuitBreakerLib.getThreshold(key);
    }

    /// @inheritdoc ICircuitBreaker
    function getCumulative(bytes32 key) public view virtual returns (uint256 cumulative, uint48 windowStart) {
        return CircuitBreakerLib.getCumulative(key);
    }

    /// @inheritdoc ICircuitBreaker
    function setThreshold(bytes32 key, uint256 threshold, uint48 windowSeconds) public virtual {
        CircuitBreakerLib.setThreshold(key, threshold, windowSeconds);
    }

    /// @inheritdoc ICircuitBreaker
    function recordObservation(bytes32 key, uint256 value) public virtual {
        CircuitBreakerLib.recordObservation(key, value);
    }

    /// @inheritdoc ICircuitBreaker
    function reset(bytes32 key) public virtual {
        CircuitBreakerLib.reset(key);
    }
}
