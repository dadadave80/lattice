// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";

/// @title ERC20Init
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a base ERC-20 diamond — seeds name/symbol (and registers IERC20 via
///         ERC-165). Delegatecalled by {Lattice.initialize} inside the initializing window (so it must NOT
///         open its own pre/postInitializer; the `__ERC20_init` guard passes because the window is already
///         open). Companion to the {AccountInit} pattern — a first-class production deploy artifact.
/// @custom:lattice-kind step
contract ERC20Init {
    /// @custom:lattice-initializes ERC20;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-param name_;
    /// @custom:lattice-param symbol_;
    /// @custom:lattice-registers-interfaces
    function init(string memory name_, string memory symbol_) external {
        ERC20Lib.__ERC20_init(name_, symbol_);
    }
}
