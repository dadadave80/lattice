// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {GelatoAutomateAdapterLib} from "@lattice/oracles/libraries/GelatoAutomateAdapterLib.sol";

/// @title GelatoAutomateAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Gelato Automate adapter diamond — registers the IGelatoAutomateAdapter
///         interface (ERC-165) and seeds AccessControl so `setConfig`/`createTask`/`cancelTask` are admin-gated.
///         Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT open its own
///         pre/postInitializer; each `__*_init` guard passes because the window is already open). Companion to
///         the {ERC2981Init}/{EmergencyStopInit} patterns — a first-class production deploy artifact. The Gelato
///         Automate contract + dedicated msg.sender are configured post-deploy via the admin-gated `setConfig`.
contract GelatoAutomateAdapterInit {
    /// @notice Runs the Gelato Automate adapter + access-control module initializers. MUST be invoked via the
    ///         diamond's `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls `setConfig`/`createTask`/`cancelTask`).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        GelatoAutomateAdapterLib.__GelatoAutomateAdapter_init();
    }
}
