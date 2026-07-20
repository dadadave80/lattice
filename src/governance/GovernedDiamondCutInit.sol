// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib} from "@diamond/libraries/DiamondLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {GovernedDiamondCutLib} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";

/// @title GovernedDiamondCutInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a governed diamond-cut diamond — seeds AccessControl (so guardian
///         management + `emergencyResume` are `DEFAULT_ADMIN_ROLE`-gated), EmergencyStop, registers the
///         IDiamondCut + IDiamondLoupe ERC-165 flags, and pins `UPGRADE_EXECUTOR_ROLE` to itself (granted
///         to `address(this)`). Delegatecalled by {Diamond.initialize} inside the initializing window (so
///         it must NOT open its own pre/postInitializer; each `__*_init` guard passes because the window is
///         already open). Mirrors exactly what the old `MockGovernedDiamond.initialize` did, minus the
///         redundant pre/postInitializer. Companion to the {ERC2981Init} pattern — a
///         first-class production deploy artifact.
contract GovernedDiamondCutInit {
    /// @notice Runs the access-control + emergency-stop + governed-cut module initializers. MUST be invoked
    ///         via the diamond's `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (manages guardians and resumes operation).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        EmergencyStopLib.__EmergencyStop_init();
        DiamondLib.registerInterface(); // ERC-165 flags for IDiamondCut (0x1f931c1c) + IDiamondLoupe
        GovernedDiamondCutLib.__GovernedDiamondCut_init();
    }
}
