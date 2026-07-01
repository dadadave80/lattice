// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {LayerZeroGatewayAdapterLib} from "@lattice/crosschain/libraries/LayerZeroGatewayAdapterLib.sol";

/// @title LayerZeroGatewayAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a LayerZero gateway-adapter diamond — seeds AccessControl so the eid, peer
///         and destination setters are admin-gated, and wires the LayerZero v2 EndpointV2 (registering the
///         ERC-7786 gateway-source interface via ERC-165). The adapter is its own OApp; `setDelegate` is NOT
///         called here (only needed to reconfigure LayerZero libs later). Delegatecalled by {Diamond.initialize}
///         inside the initializing window (so it must NOT open its own pre/postInitializer; each `__*_init`
///         guard passes because the window is already open). Companion to the {CCIPGatewayAdapterInit} pattern —
///         a first-class production deploy artifact.
contract LayerZeroGatewayAdapterInit {
    /// @notice Runs the access-control + LayerZero-adapter module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param endpoint The LayerZero v2 EndpointV2 the adapter dispatches `send` to and accepts `lzReceive` from.
    function init(address admin, address endpoint) external {
        AccessControlLib.__AccessControl_init(admin);
        LayerZeroGatewayAdapterLib.__LayerZeroGatewayAdapter_init(endpoint);
    }
}
