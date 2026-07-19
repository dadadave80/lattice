// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AxelarGatewayAdapterLib} from "@lattice/crosschain/axelar/AxelarGatewayAdapterLib.sol";

/// @title AxelarGatewayAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an Axelar gateway-adapter diamond — seeds AccessControl so the
///         chain-equivalence and remote-gateway setters are admin-gated, and wires the Axelar gateway (registering
///         the ERC-7786 interface via ERC-165). Delegatecalled by {Diamond.initialize} inside the initializing
///         window (so it must NOT open its own pre/postInitializer; each `__*_init` guard passes because the window
///         is already open). Companion to the {ERC2981Init} and {ChainlinkAdapterInit} patterns — a first-class
///         production deploy artifact.
contract AxelarGatewayAdapterInit {
    /// @notice Runs the access-control + Axelar-adapter module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param gateway The Axelar gateway the adapter dispatches `callContract` to and validates inbound calls with.
    function init(address admin, address gateway) external {
        AccessControlLib.__AccessControl_init(admin);
        AxelarGatewayAdapterLib.__AxelarGatewayAdapter_init(gateway);
    }
}
