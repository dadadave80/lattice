// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC721URIStorageLib} from "@lattice/tokens/ERC721/libraries/ERC721URIStorageLib.sol";

/// @title ERC721URIStorage
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721URIStorage.sol)
/// @notice Stateless Diamond facet for ERC-721 with per-token URI storage (EIP-4906).
/// @dev Owns ONLY its own selectors — `setTokenURI` (new) and `tokenURI`, which REPLACES the base {ERC721}
///      variant to read per-token URI storage. It does NOT inherit the {ERC721} facet — doing so would re-export
///      the base ERC-721 surface and collide with the standalone {ERC721} facet in a Diamond (and `is
///      IERC721URIStorage` would drag in the whole IERC721 surface, forcing a re-export). The ERC-721 base
///      surface comes from a separately-cut {ERC721} facet; {DeployERC721URIStorage} composes both. The EIP-4906
///      metadata-update events are emitted by {ERC721URIStorageLib}. Pure delegator pattern.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract ERC721URIStorage {
    /// @notice Returns the URI for `tokenId`.
    /// @dev Replaces the base {ERC721} `tokenURI` to use per-token URI storage.
    function tokenURI(uint256 tokenId) public view virtual returns (string memory) {
        return ERC721URIStorageLib.tokenURI(tokenId);
    }

    /// @notice Sets the per-token URI for `tokenId`. Admin-gated.
    function setTokenURI(uint256 tokenId, string memory uri) public virtual {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC721URIStorageLib._setTokenURI(tokenId, uri);
    }
}
