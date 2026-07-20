// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {WormholeGatewayAdapterLib} from "@lattice/crosschain/wormhole/WormholeGatewayAdapterLib.sol";

/// @title WormholeGatewayAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Wormhole gateway-adapter diamond — seeds AccessControl so the
///         chain-equivalence and remote-gateway setters are admin-gated, and wires the Wormhole relayer plus this
///         chain's Wormhole chain id (registering the ERC-7786 interface via ERC-165). Delegatecalled by
///         {Diamond.initialize} inside the initializing window (so it must NOT open its own pre/postInitializer;
///         each `__*_init` guard passes because the window is already open). Companion to the {ERC2981Init} and
///         {ChainlinkAdapterInit} patterns — a first-class production deploy artifact.
contract WormholeGatewayAdapterInit {
    /// @notice Runs the access-control + Wormhole-adapter module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param relayer The Wormhole relayer the adapter dispatches `sendPayloadToEvm` to and accepts deliveries from.
    /// @param wormholeChainId This chain's Wormhole chain id.
    function init(address admin, address relayer, uint16 wormholeChainId) external {
        AccessControlLib.__AccessControl_init(admin);
        WormholeGatewayAdapterLib.__WormholeGatewayAdapter_init(relayer, wormholeChainId);
    }
}
