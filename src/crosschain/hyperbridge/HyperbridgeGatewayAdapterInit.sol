// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {HyperbridgeGatewayAdapterLib} from "@lattice/crosschain/hyperbridge/HyperbridgeGatewayAdapterLib.sol";

/// @title HyperbridgeGatewayAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Hyperbridge gateway-adapter diamond — seeds AccessControl (so the state
///         machine, remote-module and timeout setters are admin-gated), the reentrancy guard (the host-invoked
///         callbacks and native quote/dispatch/refund path are `nonReentrant`), and wires the Hyperbridge IsmpHost
///         (zero reverts), registering BOTH the ERC-7786 gateway-source interface (shared) and the adapter's
///         own IHyperbridgeGatewayAdapter interface via ERC-165. Fees use the live host fee token or its
///         compatible native swap path, so no fee configuration is cached here. Delegatecalled by
///         {Lattice.initialize} inside the initializing window (so it must NOT open its own
///         pre/postInitializer; each `__*_init` guard passes because the window is already open). Companion to
///         the {HyperlaneGatewayAdapterInit}/{CCTPBridgeAdapterInit} pattern — a first-class production deploy
///         artifact.
/// @custom:lattice-kind bundle
contract HyperbridgeGatewayAdapterInit {
    /// @notice Runs the access-control + reentrancy-guard + Hyperbridge-adapter module initializers. MUST be
    ///         invoked via the diamond's `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param host  The Hyperbridge IsmpHost the adapter dispatches to and accepts module callbacks from.
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-initializes HyperbridgeGatewayAdapter;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence AccessControl;HyperbridgeGatewayAdapter;
    /// @custom:lattice-param admin authority;
    /// @custom:lattice-param host;
    /// @custom:lattice-registers-interfaces
    function init(address admin, address host) external {
        AccessControlLib.__AccessControl_init(admin);
        HyperbridgeGatewayAdapterLib.__HyperbridgeGatewayAdapter_init(host);
    }
}
