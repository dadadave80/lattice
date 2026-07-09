// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";

/// @title EmergencyStopTestFacet
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only facet exposing the internal {EmergencyStopLib.checkNotStopped} consumer guard the production
///         {EmergencyStop} facet does not surface (it is meant to gate app-specific operations). Cut ON TOP of
///         the production {DeployEmergencyStop} recipe so a facet test can prove an active stop blocks a real
///         action through the REAL diamond dispatch — never shipped, never part of a `run()` deploy.
contract EmergencyStopTestFacet {
    /// @notice External action that reverts (`EmergencyStopActive`) when the emergency stop is active.
    function gatedAction() external view {
        EmergencyStopLib.checkNotStopped();
    }
}
