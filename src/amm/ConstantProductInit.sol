// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ConstantProductLib} from "@lattice/amm/libraries/ConstantProductLib.sol";

/// @title ConstantProductInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a ConstantProduct AMM diamond — seeds AccessControl (so any admin-gated
///         operation is `DEFAULT_ADMIN_ROLE`-gated) and binds the pool to its two ERC-20 reserve tokens
///         (sorted token0 < token1), registering IConstantProduct via ERC-165 and arming the reentrancy guard.
///         Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT open its own
///         pre/postInitializer; each `__*_init` guard passes because the window is already open). Companion to
///         the {ERC2981Init}/{VaultCoreInit} patterns — a first-class production deploy artifact.
contract ConstantProductInit {
    /// @notice Runs the access-control + ConstantProduct module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param tokenA One of the two pool reserve tokens.
    /// @param tokenB The other pool reserve token.
    function init(address admin, address tokenA, address tokenB) external {
        AccessControlLib.__AccessControl_init(admin);
        ConstantProductLib.__ConstantProduct_init(tokenA, tokenB);
    }
}
