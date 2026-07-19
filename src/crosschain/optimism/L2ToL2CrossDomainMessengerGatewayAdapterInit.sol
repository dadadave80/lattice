// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {
    L2ToL2CrossDomainMessengerGatewayAdapterLib
} from "@lattice/crosschain/optimism/L2ToL2CrossDomainMessengerGatewayAdapterLib.sol";

/// @title L2ToL2CrossDomainMessengerGatewayAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an OP Superchain `L2ToL2CrossDomainMessenger` gateway-adapter diamond — seeds
///         AccessControl so the remote-adapter setter is admin-gated, and registers the ERC-7786 gateway-source
///         interface via ERC-165. Unlike the {LayerZeroGatewayAdapterInit} / {CCIPGatewayAdapterInit} siblings
///         there is NO endpoint/router ctor arg: the messenger is the fixed predeploy constant
///         (`0x4200000000000000000000000000000000000023`). Delegatecalled by {Diamond.initialize} inside the
///         initializing window (so it must NOT open its own pre/postInitializer; each `__*_init` guard passes
///         because the window is already open). A first-class production deploy artifact.
contract L2ToL2CrossDomainMessengerGatewayAdapterInit {
    /// @notice Runs the access-control + adapter module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the remote-adapter setter).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        L2ToL2CrossDomainMessengerGatewayAdapterLib.__L2ToL2CrossDomainMessengerGatewayAdapter_init();
    }
}
