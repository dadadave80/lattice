// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC721Burnable
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721Burnable.sol)
/// @notice Interface for burnable ERC-721 tokens. Its interfaceId is `0x42966c68`, the `burn(uint256)` selector.
interface IERC721Burnable {
    /// @notice Destroys `tokenId`. The caller must own it, be its approved address, or be an approved operator.
    function burn(uint256 tokenId) external;
}
