// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721WrapperLib} from "@lattice/tokens/ERC721/libraries/ERC721WrapperLib.sol";

/// @title ERC721WrapperInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ERC-721 Wrapper extension — records the underlying collection and registers
///         IERC721Wrapper via ERC-165. Delegatecalled by {Diamond.initialize} (through {MultiInit}) inside the
///         initializing window opened by the diamond, alongside the base {ERC721Init}; it must NOT open its own
///         pre/postInitializer.
contract ERC721WrapperInit {
    function init(address underlying_) external {
        ERC721WrapperLib.__ERC721Wrapper_init(underlying_);
    }
}
