// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IERC721URIStorage} from "@lattice/interfaces/IERC721URIStorage.sol";
import {ERC721} from "@lattice/tokens/ERC721.sol";
import {ERC721URIStorageLib} from "@lattice/tokens/libraries/ERC721URIStorageLib.sol";

/// @title ERC721URIStorage
/// @notice Stateless Diamond facet for ERC-721 with per-token URI storage (EIP-4906).
/// @dev Inherits ERC721 and overrides tokenURI to use per-token URI storage.
///      Implements IERC721URIStorage for EIP-4906 events. Pure delegator pattern.
contract ERC721URIStorage is ERC721 {
    /// @notice Returns the URI for `tokenId`.
    /// @dev Overrides ERC721.tokenURI to use per-token URI storage.
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        return ERC721URIStorageLib.tokenURI(tokenId);
    }

    /// @notice Sets the per-token URI for `tokenId`. Admin-gated.
    function setTokenURI(uint256 tokenId, string memory uri) public virtual {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC721URIStorageLib._setTokenURI(tokenId, uri);
    }
}
