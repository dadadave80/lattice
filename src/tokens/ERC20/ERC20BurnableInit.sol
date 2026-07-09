// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20BurnableLib} from "@lattice/tokens/ERC20/libraries/ERC20BurnableLib.sol";

/// @title ERC20BurnableInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ERC-20 Burnable extension — registers IERC20Burnable via ERC-165.
///         Delegatecalled by {Diamond.initialize} (through {MultiInit}) inside the initializing window opened by
///         the diamond, alongside the base {ERC20Init}; it must NOT open its own pre/postInitializer.
contract ERC20BurnableInit {
    function init() external {
        ERC20BurnableLib.__ERC20Burnable_init();
    }
}
