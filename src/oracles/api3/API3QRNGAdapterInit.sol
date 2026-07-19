// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {API3QRNGAdapterLib} from "@lattice/oracles/api3/API3QRNGAdapterLib.sol";

/// @title API3QRNGAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an API3 QRNG randomness diamond — seeds AccessControl so the QRNG config +
///         request setters are admin-gated, and registers the IAPI3QRNGAdapter interface (ERC-165).
///         Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT open its own
///         pre/postInitializer; each `__*_init` guard passes because the window is already open). Companion to
///         the {ERC2981Init}/{EmergencyStopInit} patterns — a first-class production deploy artifact.
contract API3QRNGAdapterInit {
    /// @notice Runs the QRNG + access-control module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the QRNG config + request setters).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        API3QRNGAdapterLib.__API3QRNGAdapter_init();
    }
}
