// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib} from "@diamond/libraries/DiamondLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {SafeDiamondCutLib} from "@lattice/governance/libraries/SafeDiamondCutLib.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";

/// @title SafeDiamondCutInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Safe-gated diamond-cut diamond — seeds AccessControl (so guardian
///         management + `emergencyResume` are `DEFAULT_ADMIN_ROLE`-gated), EmergencyStop, registers the
///         IDiamondCut + IDiamondLoupe ERC-165 flags, and pins the Safe authority + minimum threshold.
///         Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT open its
///         own pre/postInitializer; each `__*_init` guard passes because the window is already open).
///         Mirrors exactly what the old `MockSafeDiamond.initialize` did, minus the redundant
///         pre/postInitializer. Companion to the {ERC2981Init}/{EmergencyStopInit} patterns — a first-class
///         production deploy artifact.
contract SafeDiamondCutInit {
    /// @notice Runs the access-control + emergency-stop + Safe-cut module initializers. MUST be invoked via
    ///         the diamond's `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (manages guardians and resumes operation).
    /// @param safe The Gnosis Safe multisig pinned as the sole cut authority.
    /// @param minThreshold The minimum signature threshold the pinned Safe must enforce.
    function init(address admin, address safe, uint256 minThreshold) external {
        AccessControlLib.__AccessControl_init(admin);
        EmergencyStopLib.__EmergencyStop_init();
        DiamondLib.registerInterface(); // ERC-165 flags for IDiamondCut (0x1f931c1c) + IDiamondLoupe
        SafeDiamondCutLib.__SafeDiamondCut_init(safe, minThreshold);
    }
}
