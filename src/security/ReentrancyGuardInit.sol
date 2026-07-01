// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

/// @title ReentrancyGuardInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ReentrancyGuard module — registers the IReentrancyGuard interface
///         (ERC-165) and seeds the lock status to `_NOT_ENTERED`. Delegatecalled by {Diamond.initialize} inside
///         the initializing window (so it must NOT open its own pre/postInitializer; `__ReentrancyGuard_init`'s
///         guard passes because the window is already open). ReentrancyGuard has no standalone external selectors
///         (it is a guard consumed by other facets), so there is no production facet — the guard is exercised by a
///         test-only facet that calls `nonReentrantBefore/After` under real diamond delegatecall.
contract ReentrancyGuardInit {
    /// @notice Runs the reentrancy-guard module initializer. MUST be invoked via the diamond's `initialize`
    ///         `_init` delegatecall.
    function init() external {
        ReentrancyGuardLib.__ReentrancyGuard_init();
    }
}
