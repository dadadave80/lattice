// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC721Burnable} from "@lattice/interfaces/tokens/IERC721Burnable.sol";
import {ERC721BurnableLib} from "@lattice/tokens/ERC721/libraries/ERC721BurnableLib.sol";

/// @title ERC721Burnable
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721Burnable.sol)
/// @notice Stateless Diamond facet adding `burn(tokenId)` to ERC-721. Pure delegator to {ERC721BurnableLib}.
/// @dev Additive: cut it next to the base {ERC721} facet. `burn(uint256)` is also the {ERC20Burnable} selector,
///      so the two cannot share a diamond. It burns through {ERC721Lib}, so it must not share a diamond with
///      {ERC721Enumerable} or {ERC721Votes}, and {ERC721Pausable} does not pause it (D25).
/// @custom:lattice-version 0.5.0
/// @custom:lattice-source OpenZeppelin v5.6.1
contract ERC721Burnable is IERC721Burnable {
    /// @inheritdoc IERC721Burnable
    function burn(uint256 tokenId) public virtual {
        ERC721BurnableLib.burn(tokenId);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC721Burnable methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `burn(uint256)` 0x42966c68
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"42966c68";
    }
}
