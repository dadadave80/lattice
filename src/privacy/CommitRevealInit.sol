// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CommitRevealLib} from "@lattice/privacy/libraries/CommitRevealLib.sol";

/// @title CommitRevealInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a CommitReveal diamond — registers the ICommitReveal interface (ERC-165).
///         The primitive is permissionless (anyone may commit/reveal their own), so there is NO AccessControl in
///         the recipe. Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT open
///         its own pre/postInitializer; the `__CommitReveal_init` guard passes because the window is already open).
contract CommitRevealInit {
    /// @notice Runs the commit-reveal module initializer. MUST be invoked via the diamond's `initialize`
    ///         `_init` delegatecall.
    function init() external {
        CommitRevealLib.__CommitReveal_init();
    }
}
