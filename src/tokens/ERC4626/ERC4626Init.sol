// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC4626Lib} from "@lattice/tokens/ERC4626/libraries/ERC4626Lib.sol";

/// @title ERC4626Init
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an ERC-4626 tokenized-vault diamond. The vault's shares ARE an ERC-20
///         token, so this seeds BOTH modules in a single initializing window: `__ERC20_init` (share
///         name/symbol) then `__ERC4626_init` (underlying asset + virtual-share decimals offset, which also
///         registers IERC4626 via ERC-165). Delegatecalled by {Lattice.initialize} inside the initializing
///         window — it must NOT open its own pre/postInitializer; each `__*_init` guard passes because the
///         window is already open. Companion to the {ERC20Init} pattern — a first-class production deploy
///         artifact shared by `run --broadcast` and the facet tests.
/// @custom:lattice-kind bundle
contract ERC4626Init {
    /// @notice Seeds the ERC-20 share metadata and the ERC-4626 vault parameters.
    /// @param asset_ The underlying ERC-20 asset the vault holds.
    /// @param name_ The vault share token name.
    /// @param symbol_ The vault share token symbol.
    /// @param decimalsOffset_ Virtual-share decimals offset for inflation-attack mitigation (usually 0).
    /// @custom:lattice-initializes ERC20;
    /// @custom:lattice-initializes ERC4626;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence ERC20;ERC4626;
    /// @custom:lattice-param asset_;
    /// @custom:lattice-param name_;
    /// @custom:lattice-param symbol_;
    /// @custom:lattice-param decimalsOffset_;
    /// @custom:lattice-registers-interfaces
    function init(address asset_, string memory name_, string memory symbol_, uint8 decimalsOffset_) external {
        ERC20Lib.__ERC20_init(name_, symbol_);
        ERC4626Lib.__ERC4626_init(asset_, decimalsOffset_);
    }
}
