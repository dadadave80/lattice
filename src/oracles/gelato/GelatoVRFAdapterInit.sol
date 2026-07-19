// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {GelatoVRFAdapterLib} from "@lattice/oracles/gelato/GelatoVRFAdapterLib.sol";

/// @title GelatoVRFAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Gelato VRF randomness diamond — seeds AccessControl so the operator +
///         request setters are admin-gated, and registers the IGelatoVRFAdapter interface (ERC-165).
///         Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT open its own
///         pre/postInitializer; each `__*_init` guard passes because the window is already open). Companion to
///         the {ERC2981Init}/{EmergencyStopInit} patterns — a first-class production deploy artifact.
contract GelatoVRFAdapterInit {
    /// @notice Runs the Gelato VRF + access-control module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the operator + request setters).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        GelatoVRFAdapterLib.__GelatoVRFAdapter_init();
    }
}
