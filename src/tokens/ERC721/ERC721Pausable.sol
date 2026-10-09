// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {ERC721Lib} from "@lattice/tokens/ERC721/libraries/ERC721Lib.sol";

/// @title ERC721Pausable
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721Pausable.sol)
/// @notice Stateless Diamond facet — ERC-721 whose token transfers can be paused.
/// @dev Reuses the shared {PausableLib} pause state (no new storage or interface): the diamond also cuts the
///      {Pausable} facet for the admin-gated `pause()`/`unpause()`. Under the 0.5.0 token hook model (D25, option
///      (a)) the base {ERC721Lib} has no hook, so this facet REPLACES the base movement selectors it gates:
///      `transferFrom` and both `safeTransferFrom` overloads.
///      Differences from OpenZeppelin v5.6.1, which gates `_update` with `whenNotPaused`:
///      - Only those three selectors are gated. A mint, burn or `_transfer` that another facet runs through
///        {ERC721Lib} (an app facet, {ERC721Burnable}'s `burn`, {ERC721Wrapper}'s `depositFor`/`withdrawTo`/
///        `onERC721Received`) still runs while paused. A composing facet that must respect the pause calls
///        {PausableLib.checkNotPaused} itself.
///      - It replaces the same selectors as {ERC721Enumerable} and {ERC721Votes}, so it is mutually exclusive with
///        them: one ERC-721 movement override per diamond (pinned by SelectorCompatibilityTest).
///      - `pause()`/`unpause()` come from the {Pausable} facet, gated on `DEFAULT_ADMIN_ROLE`; OpenZeppelin leaves
///        them to the deriving contract.
/// @custom:lattice-version 0.5.0
/// @custom:lattice-source OpenZeppelin v5.6.1
contract ERC721Pausable {
    /// @notice Transfers `tokenId` from `from` to `to`, reverting {IPausable-EnforcedPause} while paused (replaces
    ///         the base `transferFrom`).
    function transferFrom(address from, address to, uint256 tokenId) public virtual {
        PausableLib.checkNotPaused();
        // slither-disable-next-line arbitrary-send-erc20 ERC721Lib checks owner/approval first
        ERC721Lib.transferFrom(from, to, tokenId);
    }

    /// @notice Safely transfers `tokenId`, reverting {IPausable-EnforcedPause} while paused (replaces the base).
    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual {
        PausableLib.checkNotPaused();
        ERC721Lib.safeTransferFrom(from, to, tokenId, "");
    }

    /// @notice Safely transfers `tokenId` with `data`, reverting {IPausable-EnforcedPause} while paused (replaces
    ///         the base).
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) public virtual {
        PausableLib.checkNotPaused();
        ERC721Lib.safeTransferFrom(from, to, tokenId, data);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC721Pausable methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `safeTransferFrom(address,address,uint256)` 0x42842e0e
    ///      `safeTransferFrom(address,address,uint256,bytes)` 0xb88d4fde
    ///      `transferFrom(address,address,uint256)` 0x23b872dd
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"42842e0eb88d4fde23b872dd";
    }
}
