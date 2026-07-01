// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {StrategyManagerLib} from "@lattice/defi/libraries/StrategyManagerLib.sol";

/// @title StrategyManagerInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a StrategyManager diamond — grants `DEFAULT_ADMIN_ROLE` to `admin` (all
///         vault/strategy administration is admin-gated) and registers IStrategyManager via ERC-165.
///         Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT open its own
///         pre/postInitializer; each `__*_init` guard passes because the window is already open). Companion to
///         the {VaultCoreInit}/{ERC2981Init} patterns — a first-class production deploy artifact.
contract StrategyManagerInit {
    /// @notice Runs the access-control + StrategyManager module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        StrategyManagerLib.__StrategyManager_init();
    }
}
