// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721Lib} from "@lattice/tokens/ERC721/libraries/ERC721Lib.sol";
import {ERC721URIStorageLib} from "@lattice/tokens/ERC721/libraries/ERC721URIStorageLib.sol";

/// @title ERC721TestFacet
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only facet exposing the internal ERC-721 mint/burn/transfer primitives the production facets
///         deliberately gate (production minting is app-specific / access-controlled). It is cut ON TOP of the
///         production {DeployERC721} / {DeployERC721URIStorage} recipes so a facet test can seed token state
///         while still exercising the REAL diamond dispatch for every standard call — never shipped, never
///         part of a `run()` deploy. `setTokenURIRaw` bypasses the facet's admin gate to seed per-token URIs.
contract ERC721TestFacet {
    function mint(address to, uint256 tokenId) external {
        ERC721Lib._mint(to, tokenId);
    }

    function safeMint(address to, uint256 tokenId) external {
        ERC721Lib._safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) external {
        ERC721Lib._burn(tokenId);
    }

    function transfer(address from, address to, uint256 tokenId) external {
        ERC721Lib._transfer(from, to, tokenId);
    }

    function safeTransfer(address from, address to, uint256 tokenId) external {
        ERC721Lib._safeTransfer(from, to, tokenId, "");
    }

    /// @notice Sets a per-token URI directly (bypassing the facet's `DEFAULT_ADMIN_ROLE` gate) for seeding.
    function setTokenURIRaw(uint256 tokenId, string memory uri) external {
        ERC721URIStorageLib._setTokenURI(tokenId, uri);
    }
}
