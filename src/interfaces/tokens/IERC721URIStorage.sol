// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IERC721} from "@lattice/interfaces/tokens/IERC721.sol";

/// @title IERC721URIStorage
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721URIStorage.sol)
/// @notice Interface for ERC-721 with per-token URI storage (EIP-4906 metadata update events).
interface IERC721URIStorage is IERC721 {
    /// @dev Emitted when the metadata of `_tokenId` is updated.
    /// @param _tokenId The token whose metadata was updated.
    event MetadataUpdate(uint256 _tokenId);

    /// @dev Emitted when the metadata of tokens from `_fromTokenId` to `_toTokenId` is updated.
    /// @param _fromTokenId The first token in the range.
    /// @param _toTokenId The last token in the range.
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
}
