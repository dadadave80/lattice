// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {CCIPGatewayAdapterLib} from "@lattice/crosschain/libraries/CCIPGatewayAdapterLib.sol";

/// @title CCIPGatewayAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a CCIP gateway-adapter diamond — seeds AccessControl so the chain-selector,
///         remote-gateway, destination and fee-token setters are admin-gated, and wires the CCIP router plus the
///         initial fee token (registering the ERC-7786 / CCIP-receiver interfaces via ERC-165). Delegatecalled by
///         {Diamond.initialize} inside the initializing window (so it must NOT open its own pre/postInitializer;
///         each `__*_init` guard passes because the window is already open). Companion to the {ERC2981Init} and
///         {ChainlinkAdapterInit} patterns — a first-class production deploy artifact.
contract CCIPGatewayAdapterInit {
    /// @notice Runs the access-control + CCIP-adapter module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param router The CCIP router the adapter dispatches `ccipSend` to and accepts `ccipReceive` from.
    /// @param feeToken The initial CCIP fee token (`address(0)` = pay fees in native gas).
    function init(address admin, address router, address feeToken) external {
        AccessControlLib.__AccessControl_init(admin);
        CCIPGatewayAdapterLib.__CCIPGatewayAdapter_init(router, feeToken);
    }
}
