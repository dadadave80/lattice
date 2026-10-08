// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721EnumerableLib} from "@lattice/tokens/ERC721/libraries/ERC721EnumerableLib.sol";

/// @title ERC721EnumerableInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ERC-721 Enumerable extension — registers IERC721Enumerable via ERC-165.
///         Delegatecalled by {Diamond.initialize} (through {MultiInit}) inside the initializing window opened by
///         the diamond, alongside the base {ERC721Init}; it must NOT open its own pre/postInitializer.
contract ERC721EnumerableInit {
    function init() external {
        ERC721EnumerableLib.__ERC721Enumerable_init();
    }
}
