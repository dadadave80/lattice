// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC721Receiver} from "@lattice/interfaces/tokens/IERC721.sol";
import {IERC721Wrapper} from "@lattice/interfaces/tokens/IERC721Wrapper.sol";
import {ERC721WrapperLib} from "@lattice/tokens/ERC721/libraries/ERC721WrapperLib.sol";

/// @title ERC721Wrapper
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721Wrapper.sol)
/// @notice Stateless Diamond facet — wraps an underlying ERC-721 id for id. Pure delegator to {ERC721WrapperLib}.
/// @dev Additive: every selector is new next to the base {ERC721} facet. `recover` is intentionally NOT exposed:
///      exposing it requires access control, so a deriving facet adds it.
///      RECEIVER SEAM: `onERC721Received` (0x150b7a02) is also served by {UniswapV3Adapter}, so the two cannot share
///      a diamond (issue #201 tracks declaring such seams). This facet accepts safe transfers only from the
///      underlying collection and reverts for every other ERC-721.
///      CUSTODY: the diamond escrows the underlying ids. One custodian of a collection per diamond.
///      It mints and burns through {ERC721Lib}, so it must not share a diamond with {ERC721Enumerable} or
///      {ERC721Votes}, and {ERC721Pausable} does not pause it (D25).
/// @custom:lattice-version 0.5.0
/// @custom:lattice-source OpenZeppelin v5.6.1
contract ERC721Wrapper is IERC721Wrapper, IERC721Receiver {
    /// @inheritdoc IERC721Wrapper
    function underlying() public view virtual returns (address) {
        return ERC721WrapperLib.underlying();
    }

    /// @inheritdoc IERC721Wrapper
    function depositFor(address account, uint256[] memory tokenIds) public virtual returns (bool) {
        return ERC721WrapperLib.depositFor(account, tokenIds);
    }

    /// @inheritdoc IERC721Wrapper
    function withdrawTo(address account, uint256[] memory tokenIds) public virtual returns (bool) {
        return ERC721WrapperLib.withdrawTo(account, tokenIds);
    }

    /// @notice Mints the wrapped id to `from` when the underlying collection safely transfers a token in.
    /// @dev Reverts {IERC721Wrapper.ERC721UnsupportedToken} unless the caller is the underlying collection.
    function onERC721Received(address operator, address from, uint256 tokenId, bytes memory data)
        public
        virtual
        returns (bytes4)
    {
        return ERC721WrapperLib.onERC721Received(operator, from, tokenId, data);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC721Wrapper methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `depositFor(address,uint256[])` 0xcace6eb2
    ///      `onERC721Received(address,address,uint256,bytes)` 0x150b7a02
    ///      `underlying()` 0x6f307dc3
    ///      `withdrawTo(address,uint256[])` 0x7c1b126c
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"cace6eb2150b7a026f307dc37c1b126c";
    }
}
