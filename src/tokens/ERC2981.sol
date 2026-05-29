// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC2981Lib} from "@lattice/tokens/libraries/ERC2981Lib.sol";
import {IERC2981} from "@lattice/interfaces/IERC2981.sol";

/// @title ERC2981
/// @notice Stateless Diamond facet for the ERC-2981 NFT Royalty Standard.
/// @dev All logic lives in ERC2981Lib. This contract is a pure delegator.
///      Admin-gated mutation functions use AccessControl for authorization.
contract ERC2981 is IERC2981 {
    /// @inheritdoc IERC2981
    function royaltyInfo(uint256 tokenId, uint256 salePrice) public view virtual returns (address, uint256) {
        return ERC2981Lib.royaltyInfo(tokenId, salePrice);
    }

    /// @notice Sets the default royalty receiver and fraction. Admin-gated.
    /// @param receiver The address that will receive royalties.
    /// @param feeNumerator The royalty fraction numerator (out of 10_000 basis points).
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public virtual {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC2981Lib._setDefaultRoyalty(receiver, feeNumerator);
    }

    /// @notice Deletes the default royalty configuration. Admin-gated.
    function deleteDefaultRoyalty() public virtual {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC2981Lib._deleteDefaultRoyalty();
    }

    /// @notice Sets a per-token royalty override. Admin-gated.
    /// @param tokenId The token to set the royalty for.
    /// @param receiver The address that will receive royalties.
    /// @param feeNumerator The royalty fraction numerator (out of 10_000 basis points).
    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) public virtual {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC2981Lib._setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    /// @notice Removes the per-token royalty override. Admin-gated.
    /// @param tokenId The token to reset the royalty for.
    function resetTokenRoyalty(uint256 tokenId) public virtual {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC2981Lib._resetTokenRoyalty(tokenId);
    }
}
