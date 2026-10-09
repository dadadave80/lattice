// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1155BurnableLib} from "@lattice/tokens/ERC1155/libraries/ERC1155BurnableLib.sol";

/// @title ERC1155BurnableInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ERC-1155 Burnable extension — registers IERC1155Burnable via ERC-165.
///         Delegatecalled by {Diamond.initialize} (through {MultiInit}) inside the initializing window opened by
///         the diamond, alongside the base {ERC1155Init}; it must NOT open its own pre/postInitializer.
contract ERC1155BurnableInit {
    function init() external {
        ERC1155BurnableLib.__ERC1155Burnable_init();
    }
}
