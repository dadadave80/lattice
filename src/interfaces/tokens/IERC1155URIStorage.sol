// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC1155URIStorage
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol)
/// @notice Admin surface of the ERC-1155 per-token URI storage extension. The facet also serves `uri(uint256)`,
///         which belongs to `IERC1155MetadataURI` (0x0e89341c) and is left out here so this id covers only the
///         setters. {setURI} emits the {IERC1155} `URI` event.
interface IERC1155URIStorage {
    /// @notice Sets `tokenURI` as the per-token URI of `tokenId` and emits `URI(uri(tokenId), tokenId)`.
    /// @dev An empty `tokenURI` clears the entry, so `uri(tokenId)` falls back to the ERC-1155 URI template.
    function setURI(uint256 tokenId, string calldata tokenURI) external;

    /// @notice Sets the prefix that `uri(tokenId)` prepends to every non-empty per-token URI.
    /// @dev Emits no event, as in OpenZeppelin: `URI` is per id, and a base change touches every id.
    function setBaseURI(string calldata baseURI) external;
}
