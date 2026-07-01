// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {RateLimiterLib} from "@lattice/security/libraries/RateLimiterLib.sol";

/// @title RateLimiterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a RateLimiter diamond — registers the IRateLimiter interface (ERC-165)
///         and seeds AccessControl so the `configure` setter is admin-gated. Delegatecalled by
///         {Diamond.initialize} inside the initializing window (so it must NOT open its own pre/postInitializer;
///         each `__*_init` guard passes because the window is already open). Companion to the {ERC2981Init}
///         pattern — a first-class production deploy artifact.
contract RateLimiterInit {
    /// @notice Runs the rate-limiter + access-control module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls `configure`).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        RateLimiterLib.__RateLimiter_init();
    }
}
