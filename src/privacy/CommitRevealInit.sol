// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CommitRevealLib} from "@lattice/privacy/libraries/CommitRevealLib.sol";

/// @title CommitRevealInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a CommitReveal diamond — registers the ICommitReveal interface (ERC-165).
///         The primitive is permissionless (anyone may commit/reveal their own), so there is NO AccessControl in
///         the recipe. Delegatecalled by {Lattice.initialize} inside the initializing window (so it must NOT open
///         its own pre/postInitializer; the `__CommitReveal_init` guard passes because the window is already open).
/// @custom:lattice-kind step
contract CommitRevealInit {
    /// @notice Runs the commit-reveal module initializer. MUST be invoked via the diamond's `initialize`
    ///         `_init` delegatecall.
    /// @custom:lattice-initializes CommitReveal;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-param none;
    /// @custom:lattice-registers-interfaces
    function init() external {
        CommitRevealLib.__CommitReveal_init();
    }
}
