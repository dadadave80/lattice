// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1155Lib} from "@lattice/tokens/ERC1155/libraries/ERC1155Lib.sol";

/// @title ERC1155Init
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a base ERC-1155 diamond — seeds the URI template (and registers IERC1155 +
///         IERC1155MetadataURI via ERC-165). Delegatecalled by {Diamond.initialize} inside the initializing
///         window (so it must NOT open its own pre/postInitializer; the `__ERC1155_init` guard passes because
///         the window is already open). Companion to the {ERC20Init} pattern — a first-class production deploy
///         artifact.
contract ERC1155Init {
    function init(string memory uri_) external {
        ERC1155Lib.__ERC1155_init(uri_);
    }
}
