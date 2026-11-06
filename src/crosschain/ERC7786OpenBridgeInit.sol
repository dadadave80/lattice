// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC7786OpenBridgeLib} from "@lattice/crosschain/libraries/ERC7786OpenBridgeLib.sol";

/// @title ERC7786OpenBridgeInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an ERC-7786 open-bridge diamond — seeds AccessControl so the gateway-set,
///         threshold and remote-bridge setters are admin-gated, and registers the ERC-7786 gateway-source /
///         recipient interfaces via ERC-165. Delegatecalled by {Lattice.initialize} inside the initializing window
///         (so it must NOT open its own pre/postInitializer; each `__*_init` guard passes because the window is
///         already open). Companion to the {ERC2981Init} and {ChainlinkAdapterInit} patterns — a first-class
///         production deploy artifact. The bridge starts at threshold 0 and executes nothing until configured;
///         the admin must then call `addGateway` (each gateway), `setThreshold`, and only then
///         `registerRemoteBridge` (which reverts while the threshold is 0).
/// @custom:lattice-kind bundle
contract ERC7786OpenBridgeInit {
    /// @notice Runs the access-control + open-bridge module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the gateway set, threshold and remotes).
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-initializes ERC7786OpenBridge;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence AccessControl;ERC7786OpenBridge;
    /// @custom:lattice-param admin authority;
    /// @custom:lattice-registers-interfaces
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        ERC7786OpenBridgeLib.__ERC7786OpenBridge_init();
    }
}
