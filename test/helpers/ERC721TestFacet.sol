// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721EnumerableLib} from "@lattice/tokens/ERC721/libraries/ERC721EnumerableLib.sol";
import {ERC721Lib} from "@lattice/tokens/ERC721/libraries/ERC721Lib.sol";
import {ERC721URIStorageLib} from "@lattice/tokens/ERC721/libraries/ERC721URIStorageLib.sol";
import {ERC721VotesLib} from "@lattice/tokens/ERC721/libraries/ERC721VotesLib.sol";
import {ERC721WrapperLib} from "@lattice/tokens/ERC721/libraries/ERC721WrapperLib.sol";

/// @title ERC721TestFacet
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only facet exposing the internal ERC-721 mint/burn/transfer/approval primitives the production facets
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

    /// @notice Burns `tokenId` with no authorization check. Named `burnRaw` so it never collides with the
    ///         production {ERC721Burnable} `burn(uint256)` when both are cut into one test diamond.
    function burnRaw(uint256 tokenId) external {
        ERC721Lib._burn(tokenId);
    }

    function transfer(address from, address to, uint256 tokenId) external {
        ERC721Lib._transfer(from, to, tokenId);
    }

    function safeTransfer(address from, address to, uint256 tokenId) external {
        ERC721Lib._safeTransfer(from, to, tokenId, "");
    }

    /// @notice Calls the internal `_setApprovalForAll` with an arbitrary `owner` (the facet always passes
    ///         `msg.sender`), so a test can reach the zero-owner guard.
    function setApprovalForAllRaw(address owner, address operator, bool approved) external {
        ERC721Lib._setApprovalForAll(owner, operator, approved);
    }

    /// @notice Sets a per-token URI directly (bypassing the facet's `DEFAULT_ADMIN_ROLE` gate) for seeding.
    function setTokenURIRaw(uint256 tokenId, string memory uri) external {
        ERC721URIStorageLib._setTokenURI(tokenId, uri);
    }

    /// @notice Exposes the {ERC721Wrapper} internal `recover`, which the production facet leaves out because it
    ///         needs access control. Only meaningful on a wrapper diamond.
    function recoverWrapped(address account, uint256 tokenId) external returns (uint256) {
        return ERC721WrapperLib.recover(account, tokenId);
    }

    /// @notice Mints through {ERC721EnumerableLib}, as an app mint facet on an enumerable diamond must.
    function enumerableMint(address to, uint256 tokenId) external {
        ERC721EnumerableLib._mint(to, tokenId);
    }

    /// @notice Safely mints through {ERC721EnumerableLib}.
    function enumerableSafeMint(address to, uint256 tokenId) external {
        ERC721EnumerableLib._safeMint(to, tokenId, "");
    }

    /// @notice Burns through {ERC721EnumerableLib} with no authorization check.
    function enumerableBurn(uint256 tokenId) external {
        ERC721EnumerableLib._burn(tokenId);
    }

    /// @notice Transfers through {ERC721EnumerableLib} with no authorization check.
    function enumerableTransfer(address from, address to, uint256 tokenId) external {
        ERC721EnumerableLib._transfer(from, to, tokenId);
    }

    /// @notice Safely transfers through {ERC721EnumerableLib} with no authorization check.
    function enumerableSafeTransfer(address from, address to, uint256 tokenId) external {
        ERC721EnumerableLib._safeTransfer(from, to, tokenId, "");
    }

    /// @notice Mints through {ERC721VotesLib}, as an app mint facet on a votes diamond must.
    function votesMint(address to, uint256 tokenId) external {
        ERC721VotesLib._mint(to, tokenId);
    }

    /// @notice Safely mints through {ERC721VotesLib}.
    function votesSafeMint(address to, uint256 tokenId) external {
        ERC721VotesLib._safeMint(to, tokenId, "");
    }

    /// @notice Burns through {ERC721VotesLib} with no authorization check.
    function votesBurn(uint256 tokenId) external {
        ERC721VotesLib._burn(tokenId);
    }

    /// @notice Transfers through {ERC721VotesLib} with no authorization check.
    function votesTransfer(address from, address to, uint256 tokenId) external {
        ERC721VotesLib._transfer(from, to, tokenId);
    }

    /// @notice Safely transfers through {ERC721VotesLib} with no authorization check.
    function votesSafeTransfer(address from, address to, uint256 tokenId) external {
        ERC721VotesLib._safeTransfer(from, to, tokenId, "");
    }
}
