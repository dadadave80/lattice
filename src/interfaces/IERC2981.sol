// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC2981
/// @notice Interface for the ERC-2981 NFT Royalty Standard.
interface IERC2981 {
    /// @dev `numerator` is greater than `denominator` (royalty exceeds 100%).
    error ERC2981InvalidDefaultRoyalty(uint256 numerator, uint256 denominator);

    /// @dev `receiver` is the zero address.
    error ERC2981InvalidDefaultRoyaltyReceiver(address receiver);

    /// @dev `numerator` is greater than `denominator` for the given `tokenId`.
    error ERC2981InvalidTokenRoyalty(uint256 tokenId, uint256 numerator, uint256 denominator);

    /// @dev `receiver` is the zero address for the given `tokenId`.
    error ERC2981InvalidTokenRoyaltyReceiver(uint256 tokenId, address receiver);

    /// @notice Returns royalty information for a token sale.
    /// @param tokenId The NFT being sold.
    /// @param salePrice The sale price of the NFT (in any unit of exchange).
    /// @return receiver Address of the royalty recipient.
    /// @return royaltyAmount The royalty payment amount.
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount);
}
