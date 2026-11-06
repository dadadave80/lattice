// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165_MAP_ILOUPE_SLOT} from "@diamond/libraries/DiamondLib.sol";
import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {GovernedSafeDiamondCutLib} from "@lattice/governance/libraries/GovernedSafeDiamondCutLib.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";

/// @title GovernedSafeDiamondCutInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Safe-gated, timelocked diamond-cut diamond — seeds AccessControl (so
///         guardian management + `emergencyResume` are `DEFAULT_ADMIN_ROLE`-gated), EmergencyStop, registers
///         the IERC165 + IDiamondLoupe ERC-165 flags, and pins the Safe authority + minimum threshold +
///         minimum timelock delay (the module also self-registers its own IGovernedSafeDiamondCut ERC-165
///         id `0xacb1aeb6`). Delegatecalled by {Lattice.initialize} inside the initializing window (so it
///         must NOT open its own pre/postInitializer; each `__*_init` guard passes because the window is
///         already open). Mirrors exactly what the old `MockGovernedSafeDiamond.initialize` did, minus the
///         redundant pre/postInitializer. Companion to the {ERC2981Init} pattern — a
///         first-class production deploy artifact.
/// @custom:lattice-kind bundle
contract GovernedSafeDiamondCutInit {
    /// @notice Runs the access-control + emergency-stop + governed-Safe-cut module initializers. MUST be
    ///         invoked via the diamond's `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (manages guardians and resumes operation).
    /// @param safe The Gnosis Safe multisig pinned as the sole scheduling/execution authority.
    /// @param minThreshold The minimum signature threshold the pinned Safe must enforce.
    /// @param minDelay The minimum timelock delay (seconds) between schedule and execute.
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-initializes EmergencyStop;
    /// @custom:lattice-initializes ERC165;
    /// @custom:lattice-initializes Diamond with loupe-only=true;
    /// @custom:lattice-initializes GovernedSafeDiamondCut;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence AccessControl;EmergencyStop;ERC165;Diamond;GovernedSafeDiamondCut;
    /// @custom:lattice-param admin authority;
    /// @custom:lattice-param safe authority;
    /// @custom:lattice-param minThreshold;
    /// @custom:lattice-param minDelay unit=seconds;
    /// @custom:lattice-registers-interfaces
    function init(address admin, address safe, uint256 minThreshold, uint256 minDelay) external {
        AccessControlLib.__AccessControl_init(admin);
        EmergencyStopLib.__EmergencyStop_init();
        ERC165Lib.registerInterface(); // ERC-165 flag for IERC165 (0x01ffc9a7)
        // This recipe routes delayed scheduleCut/executeCut, not IDiamondCut.diamondCut.
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ILOUPE_SLOT, true)
        }
        GovernedSafeDiamondCutLib.__GovernedSafeDiamondCut_init(safe, minThreshold, minDelay);
    }
}
