// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ChainRegistryLib} from "@lattice/crosschain/libraries/ChainRegistryLib.sol";

/// @title ChainRegistryInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a chain-registry diamond — seeds AccessControl (every registry setter and
///         the {ChainRegistry.addEvmChain} fan-out are `DEFAULT_ADMIN_ROLE`-gated) and registers the
///         IChainRegistry interface via ERC-165. There are NO module config params: the registry starts empty
///         and is populated post-deploy by the admin. Delegatecalled by {Diamond.initialize} inside the
///         initializing window (so it must NOT open its own pre/postInitializer; each `__*_init` guard passes
///         because the window is already open).
contract ChainRegistryInit {
    /// @notice Runs the access-control + chain-registry initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every registry setter and the fan-out).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        ChainRegistryLib.__ChainRegistry_init();
    }
}
