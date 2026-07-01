// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {CrosschainLinkLib} from "@lattice/crosschain/libraries/CrosschainLinkLib.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {ERC20CrosschainLib} from "@lattice/tokens/ERC20/libraries/ERC20CrosschainLib.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";

/// @title ERC20CrosschainInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a self-bridging ERC-20 diamond: seeds `AccessControl` (the crosschain-link
///         admin setters), the ReentrancyGuard used by the crosschain transfer path, the base `ERC20`
///         (name/symbol + ERC-165), the {CrosschainLink} receive/send registry, and the {ERC20Crosschain}
///         self-bridge (registers IBridgeFungible). Delegatecalled by {Diamond.initialize} inside the
///         initializing window (so it must NOT open its own pre/postInitializer; each `__*_init` guard passes
///         because the window is already open). Runs the exact `__*_init` sequence the legacy inheritance mock
///         performed, but on a REAL diamond. Companion to the {ERC20Init}/{ERC2981Init} patterns.
contract ERC20CrosschainInit {
    /// @notice Runs the access-control + reentrancy-guard + ERC-20 + crosschain-link + crosschain module
    ///         initializers. MUST be invoked via the diamond's `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls `setLink`/`setHandler`).
    /// @param name_ Token name.
    /// @param symbol_ Token symbol.
    function init(address admin, string memory name_, string memory symbol_) external {
        AccessControlLib.__AccessControl_init(admin);
        ReentrancyGuardLib.__ReentrancyGuard_init();
        ERC20Lib.__ERC20_init(name_, symbol_);
        CrosschainLinkLib.__CrosschainLink_init();
        ERC20CrosschainLib.__ERC20Crosschain_init();
    }
}
