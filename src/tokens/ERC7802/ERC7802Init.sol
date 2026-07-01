// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {CROSSCHAIN_BRIDGE_ROLE, ERC7802Lib} from "@lattice/tokens/ERC7802/libraries/ERC7802Lib.sol";

/// @title ERC7802Init
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a crosschain-native ERC-20 diamond (ERC-7802): seeds `AccessControl`,
///         the base `ERC20` (name/symbol + ERC-165), and registers the IERC7802 interface, then grants the
///         `CROSSCHAIN_BRIDGE_ROLE` to the trusted bridge. Delegatecalled by {Diamond.initialize} inside the
///         initializing window (so it must NOT open its own pre/postInitializer; each `__*_init` guard passes
///         because the window is already open). Runs the exact `__*_init` sequence the legacy inheritance mock
///         performed, but on a REAL diamond. Companion to the {ERC20Init}/{ERC2981Init} patterns.
contract ERC7802Init {
    /// @notice Runs the access-control + ERC-20 + ERC-7802 module initializers and grants the bridge role.
    ///         MUST be invoked via the diamond's `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param bridge The trusted bridge granted `CROSSCHAIN_BRIDGE_ROLE` (mints/burns crosschain supply).
    /// @param name_ Token name.
    /// @param symbol_ Token symbol.
    function init(address admin, address bridge, string memory name_, string memory symbol_) external {
        AccessControlLib.__AccessControl_init(admin);
        ERC20Lib.__ERC20_init(name_, symbol_);
        ERC7802Lib.__ERC7802_init();
        AccessControlLib._grantRole(CROSSCHAIN_BRIDGE_ROLE, bridge);
    }
}
