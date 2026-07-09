// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC2981} from "@lattice/interfaces/tokens/IERC2981.sol";
import {ERC2981Lib} from "@lattice/tokens/ERC2981/libraries/ERC2981Lib.sol";

/// @title ERC2981
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/common/ERC2981.sol)
/// @notice Stateless Diamond facet for the ERC-2981 NFT Royalty Standard.
/// @dev All logic — including admin auth — lives in `ERC2981Lib`. Pure delegator.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract ERC2981 is IERC2981 {
    /// @inheritdoc IERC2981
    function royaltyInfo(uint256 tokenId, uint256 salePrice) public view virtual returns (address, uint256) {
        return ERC2981Lib.royaltyInfo(tokenId, salePrice);
    }

    /// @notice Sets the default royalty receiver and fraction. Admin-gated.
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public virtual {
        ERC2981Lib.setDefaultRoyalty(receiver, feeNumerator);
    }

    /// @notice Deletes the default royalty configuration. Admin-gated.
    function deleteDefaultRoyalty() public virtual {
        ERC2981Lib.deleteDefaultRoyalty();
    }

    /// @notice Sets a per-token royalty override. Admin-gated.
    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) public virtual {
        ERC2981Lib.setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    /// @notice Removes the per-token royalty override. Admin-gated.
    function resetTokenRoyalty(uint256 tokenId) public virtual {
        ERC2981Lib.resetTokenRoyalty(tokenId);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC2981 methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `deleteDefaultRoyalty()` 0xaa1b103f
    ///      `resetTokenRoyalty(uint256)` 0x8a616bc0
    ///      `royaltyInfo(uint256,uint256)` 0x2a55205a
    ///      `setDefaultRoyalty(address,uint96)` 0x04634d8d
    ///      `setTokenRoyalty(uint256,address,uint96)` 0x5944c753
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"aa1b103f8a616bc02a55205a04634d8d5944c753";
    }
}
