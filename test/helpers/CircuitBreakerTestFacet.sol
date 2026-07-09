// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CircuitBreakerLib} from "@lattice/security/libraries/CircuitBreakerLib.sol";

/// @title CircuitBreakerTestFacet
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only facet exposing the internal {CircuitBreakerLib.checkNotTripped} consumer guard the
///         production {CircuitBreaker} facet does not surface (it is meant to gate app-specific operations). Cut
///         ON TOP of the production {DeployCircuitBreaker} recipe so a facet test can prove a tripped breaker
///         blocks a real action through the REAL diamond dispatch — never shipped, never part of a `run()` deploy.
contract CircuitBreakerTestFacet {
    /// @notice External action that reverts (`CircuitBreakerTrippedError`) when the circuit for `key` is tripped.
    function gatedAction(bytes32 key) external view {
        CircuitBreakerLib.checkNotTripped(key);
    }
}
