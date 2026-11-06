// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20FlashMintLib} from "@lattice/tokens/ERC20/libraries/ERC20FlashMintLib.sol";

/// @title ERC20FlashMintInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ERC-20 FlashMint (ERC-3156) extension — registers IERC3156FlashLender via
///         ERC-165. Delegatecalled by {Lattice.initialize} (through {MultiInit}) inside the initializing window
///         opened by the diamond, alongside the base {ERC20Init}; it must NOT open its own pre/postInitializer.
/// @custom:lattice-kind step
contract ERC20FlashMintInit {
    /// @custom:lattice-initializes ERC20FlashMint;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-param none;
    /// @custom:lattice-registers-interfaces
    function init() external {
        ERC20FlashMintLib.__ERC20FlashMint_init();
    }
}
