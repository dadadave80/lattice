// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {CircuitBreakerLib} from "@lattice/security/libraries/CircuitBreakerLib.sol";

/// @title CircuitBreakerInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a CircuitBreaker diamond — registers the ICircuitBreaker interface (ERC-165)
///         and seeds AccessControl so `setThreshold`/`recordObservation`/`reset` are `DEFAULT_ADMIN_ROLE`-gated.
///         Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT open its own
///         pre/postInitializer; each `__*_init` guard passes because the window is already open). Companion to
///         the {ERC2981Init} pattern — a first-class production deploy artifact.
contract CircuitBreakerInit {
    /// @notice Runs the access-control + circuit-breaker module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the breaker configuration).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        CircuitBreakerLib.__CircuitBreaker_init();
    }
}
