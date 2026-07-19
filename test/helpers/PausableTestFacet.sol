// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";

/// @title PausableTestFacet
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only facet exposing the internal {PausableLib} guard entrypoints the production {Pausable} facet
///         does not surface (they are meant to gate app-specific actions). Cut ON TOP of the production
///         {DeployPausable} recipe so a facet test can prove the `checkNotPaused()`/`checkPaused()` lib guards
///         gate a real action through the REAL diamond dispatch (the {Pausable} facade's modifiers wrap
///         these same checks; their modifier form is covered by PausableMixinTest) — never shipped, never part of a `run()` deploy.
contract PausableTestFacet {
    /// @notice External action that reverts (`EnforcedPause`) when the diamond is paused.
    function gatedAction() external view {
        PausableLib.checkNotPaused();
    }

    /// @notice External action that reverts (`ExpectedPause`) when the diamond is NOT paused.
    function pausedOnlyAction() external view {
        PausableLib.checkPaused();
    }
}
