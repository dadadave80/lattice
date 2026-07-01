// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721Lib} from "@lattice/tokens/ERC721/libraries/ERC721Lib.sol";

/// @title ERC721Init
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a base ERC-721 diamond — seeds name/symbol (and registers IERC721 +
///         IERC721Metadata via ERC-165). Delegatecalled by {Diamond.initialize} inside the initializing
///         window (so it must NOT open its own pre/postInitializer; the `__ERC721_init` guard passes because
///         the window is already open). Mirrors the {ERC20Init} pattern — a first-class production deploy
///         artifact shared by `run --broadcast` and the facet tests.
contract ERC721Init {
    function init(string memory name_, string memory symbol_) external {
        ERC721Lib.__ERC721_init(name_, symbol_);
    }
}
