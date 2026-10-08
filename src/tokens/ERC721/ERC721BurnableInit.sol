// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721BurnableLib} from "@lattice/tokens/ERC721/libraries/ERC721BurnableLib.sol";

/// @title ERC721BurnableInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ERC-721 Burnable extension — registers IERC721Burnable via ERC-165.
///         Delegatecalled by {Diamond.initialize} (through {MultiInit}) inside the initializing window opened by
///         the diamond, alongside the base {ERC721Init}; it must NOT open its own pre/postInitializer.
contract ERC721BurnableInit {
    function init() external {
        ERC721BurnableLib.__ERC721Burnable_init();
    }
}
