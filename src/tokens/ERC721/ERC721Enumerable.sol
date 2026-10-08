// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC721Enumerable} from "@lattice/interfaces/tokens/IERC721Enumerable.sol";
import {ERC721EnumerableLib} from "@lattice/tokens/ERC721/libraries/ERC721EnumerableLib.sol";

/// @title ERC721Enumerable
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721Enumerable.sol)
/// @notice Stateless Diamond facet for the EIP-721 enumeration extension. Pure delegator to {ERC721EnumerableLib}.
/// @dev Under the 0.5.0 token hook model (D25, option (a)) the base {ERC721Lib} has no hook, so this facet ADDS the
///      three enumeration views and REPLACES the base movement selectors (`transferFrom` and both
///      `safeTransferFrom` overloads) with versions that keep the lists in step. {DeployERC721Enumerable} cuts it.
///      MUTUAL EXCLUSIONS (one ERC-721 movement override per diamond):
///      - {ERC721Pausable} and {ERC721Votes} replace the same selectors (pinned by SelectorCompatibilityTest).
///      - {ERC721Burnable} and {ERC721Wrapper} mint and burn through {ERC721Lib}, which skips the lists, so neither
///        may share a diamond with this facet (pinned by CompositionHazardsTest). A mint, burn or authorization-free
///        transfer facet for an enumerable diamond calls {ERC721EnumerableLib} instead, never {ERC721Lib}.
/// @custom:lattice-version 0.5.0
/// @custom:lattice-source OpenZeppelin v5.6.1
contract ERC721Enumerable is IERC721Enumerable {
    /// @inheritdoc IERC721Enumerable
    function totalSupply() public view virtual returns (uint256) {
        return ERC721EnumerableLib.totalSupply();
    }

    /// @inheritdoc IERC721Enumerable
    function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual returns (uint256) {
        return ERC721EnumerableLib.tokenOfOwnerByIndex(owner, index);
    }

    /// @inheritdoc IERC721Enumerable
    function tokenByIndex(uint256 index) public view virtual returns (uint256) {
        return ERC721EnumerableLib.tokenByIndex(index);
    }

    /// @notice Transfers `tokenId` from `from` to `to`, updating the enumeration (replaces the base `transferFrom`).
    function transferFrom(address from, address to, uint256 tokenId) public virtual {
        // slither-disable-next-line arbitrary-send-erc20 ERC721EnumerableLib checks owner/approval first
        ERC721EnumerableLib.transferFrom(from, to, tokenId);
    }

    /// @notice Safely transfers `tokenId`, updating the enumeration (replaces the base `safeTransferFrom`).
    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual {
        ERC721EnumerableLib.safeTransferFrom(from, to, tokenId, "");
    }

    /// @notice Safely transfers `tokenId` with `data`, updating the enumeration (replaces the base
    ///         `safeTransferFrom`).
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) public virtual {
        ERC721EnumerableLib.safeTransferFrom(from, to, tokenId, data);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC721Enumerable methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `safeTransferFrom(address,address,uint256)` 0x42842e0e
    ///      `safeTransferFrom(address,address,uint256,bytes)` 0xb88d4fde
    ///      `tokenByIndex(uint256)` 0x4f6ccce7
    ///      `tokenOfOwnerByIndex(address,uint256)` 0x2f745c59
    ///      `totalSupply()` 0x18160ddd
    ///      `transferFrom(address,address,uint256)` 0x23b872dd
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"42842e0eb88d4fde4f6ccce72f745c5918160ddd23b872dd";
    }
}
