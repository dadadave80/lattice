// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC2981} from "@lattice/interfaces/IERC2981.sol";
import {ERC2981Lib} from "@lattice/tokens/libraries/ERC2981Lib.sol";

/// @title ERC2981
/// @notice Stateless Diamond facet for the ERC-2981 NFT Royalty Standard.
/// @dev All logic — including admin auth — lives in `ERC2981Lib`. Pure delegator.
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
}
