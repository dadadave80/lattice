// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";

/// @title EmergencyStopInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an EmergencyStop diamond — registers the IEmergencyStop interface (ERC-165)
///         and seeds AccessControl so guardian management + `emergencyResume` are `DEFAULT_ADMIN_ROLE`-gated
///         (guardians hold the separate `EMERGENCY_GUARDIAN_ROLE`). Delegatecalled by {Diamond.initialize} inside
///         the initializing window (so it must NOT open its own pre/postInitializer; each `__*_init` guard passes
///         because the window is already open). Companion to the {ERC2981Init} pattern — a first-class production
///         deploy artifact.
contract EmergencyStopInit {
    /// @notice Runs the access-control + emergency-stop module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (manages guardians and resumes operation).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        EmergencyStopLib.__EmergencyStop_init();
    }
}
