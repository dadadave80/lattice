// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib} from "@diamond/libraries/DiamondLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {GovernedSafeDiamondCutLib} from "@lattice/governance/libraries/GovernedSafeDiamondCutLib.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";

/// @title GovernedSafeDiamondCutInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Safe-gated, timelocked diamond-cut diamond — seeds AccessControl (so
///         guardian management + `emergencyResume` are `DEFAULT_ADMIN_ROLE`-gated), EmergencyStop, registers
///         the IDiamondCut + IDiamondLoupe ERC-165 flags, and pins the Safe authority + minimum threshold +
///         minimum timelock delay (the module also self-registers its own IGovernedSafeDiamondCut ERC-165
///         id `0xacb1aeb6`). Delegatecalled by {Diamond.initialize} inside the initializing window (so it
///         must NOT open its own pre/postInitializer; each `__*_init` guard passes because the window is
///         already open). Mirrors exactly what the old `MockGovernedSafeDiamond.initialize` did, minus the
///         redundant pre/postInitializer. Companion to the {ERC2981Init}/{EmergencyStopInit} patterns — a
///         first-class production deploy artifact.
contract GovernedSafeDiamondCutInit {
    /// @notice Runs the access-control + emergency-stop + governed-Safe-cut module initializers. MUST be
    ///         invoked via the diamond's `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (manages guardians and resumes operation).
    /// @param safe The Gnosis Safe multisig pinned as the sole scheduling/execution authority.
    /// @param minThreshold The minimum signature threshold the pinned Safe must enforce.
    /// @param minDelay The minimum timelock delay (seconds) between schedule and execute.
    function init(address admin, address safe, uint256 minThreshold, uint256 minDelay) external {
        AccessControlLib.__AccessControl_init(admin);
        EmergencyStopLib.__EmergencyStop_init();
        DiamondLib.registerInterface(); // ERC-165 flags for IDiamondCut (0x1f931c1c) + IDiamondLoupe
        GovernedSafeDiamondCutLib.__GovernedSafeDiamondCut_init(safe, minThreshold, minDelay);
    }
}
