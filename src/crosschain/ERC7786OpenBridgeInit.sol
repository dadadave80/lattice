// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC7786OpenBridgeLib} from "@lattice/crosschain/libraries/ERC7786OpenBridgeLib.sol";

/// @title ERC7786OpenBridgeInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an ERC-7786 open-bridge diamond — seeds AccessControl so the gateway-set,
///         threshold and remote-bridge setters are admin-gated, and registers the ERC-7786 gateway-source /
///         recipient interfaces via ERC-165. Delegatecalled by {Diamond.initialize} inside the initializing window
///         (so it must NOT open its own pre/postInitializer; each `__*_init` guard passes because the window is
///         already open). Companion to the {ERC2981Init} and {ChainlinkAdapterInit} patterns — a first-class
///         production deploy artifact.
contract ERC7786OpenBridgeInit {
    /// @notice Runs the access-control + open-bridge module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the gateway set, threshold and remotes).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        ERC7786OpenBridgeLib.__ERC7786OpenBridge_init();
    }
}
