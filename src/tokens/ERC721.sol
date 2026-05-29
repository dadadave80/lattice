// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC721} from "@lattice/interfaces/IERC721.sol";
import {ERC721Lib} from "@lattice/tokens/libraries/ERC721Lib.sol";

/// @title ERC721
/// @notice Stateless Diamond facet for the ERC-721 Non-Fungible Token standard.
/// @dev All logic lives in ERC721Lib. This contract is a pure delegator.
contract ERC721 is IERC721 {
    /// @inheritdoc IERC721
    function name() public view virtual returns (string memory) {
        return ERC721Lib.name();
    }

    /// @inheritdoc IERC721
    function symbol() public view virtual returns (string memory) {
        return ERC721Lib.symbol();
    }

    /// @inheritdoc IERC721
    function tokenURI(uint256 tokenId) public view virtual returns (string memory) {
        return ERC721Lib.tokenURI(tokenId);
    }

    /// @inheritdoc IERC721
    function balanceOf(address owner) public view virtual returns (uint256) {
        return ERC721Lib.balanceOf(owner);
    }

    /// @inheritdoc IERC721
    function ownerOf(uint256 tokenId) public view virtual returns (address) {
        return ERC721Lib.ownerOf(tokenId);
    }

    /// @inheritdoc IERC721
    function getApproved(uint256 tokenId) public view virtual returns (address) {
        return ERC721Lib.getApproved(tokenId);
    }

    /// @inheritdoc IERC721
    function isApprovedForAll(address owner, address operator) public view virtual returns (bool) {
        return ERC721Lib.isApprovedForAll(owner, operator);
    }

    /// @inheritdoc IERC721
    function approve(address to, uint256 tokenId) public virtual {
        ERC721Lib.approve(to, tokenId);
    }

    /// @inheritdoc IERC721
    function setApprovalForAll(address operator, bool approved) public virtual {
        ERC721Lib.setApprovalForAll(operator, approved);
    }

    /// @inheritdoc IERC721
    function transferFrom(address from, address to, uint256 tokenId) public virtual {
        ERC721Lib.transferFrom(from, to, tokenId);
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual {
        ERC721Lib.safeTransferFrom(from, to, tokenId, "");
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) public virtual {
        ERC721Lib.safeTransferFrom(from, to, tokenId, data);
    }
}
