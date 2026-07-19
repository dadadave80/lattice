// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {StargateBridgeAdapterLib} from "@lattice/crosschain/layerzero/StargateBridgeAdapterLib.sol";

/// @title StargateBridgeAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Stargate v2 token-bridge diamond — seeds AccessControl (so the
///         chainId ⇄ eid and per-token pool registrations are `DEFAULT_ADMIN_ROLE`-gated), the reentrancy
///         guard (the send path is `nonReentrant`), and registers the IStargateBridgeAdapter interface via
///         ERC-165. No protocol addresses are wired at init: Stargate is per-token pools, all registered by
///         the admin AFTER deploy ({registerEid}/{registerPool}, or via the ChainRegistry `addEvmChain`
///         fan-out for the eid map). Delegatecalled by {Diamond.initialize} inside the initializing window
///         (so it must NOT open its own pre/postInitializer; each `__*_init` guard passes because the window
///         is already open).
contract StargateBridgeAdapterInit {
    /// @notice Runs the access-control + reentrancy-guard + Stargate-adapter initializers. MUST be invoked
    ///         via the diamond's `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        StargateBridgeAdapterLib.__StargateBridgeAdapter_init();
    }
}
