// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IERC1155URIStorage} from "@lattice/interfaces/tokens/IERC1155URIStorage.sol";
import {ERC1155URIStorageLib} from "@lattice/tokens/ERC1155/libraries/ERC1155URIStorageLib.sol";

/// @title ERC1155URIStorage
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol)
/// @notice Stateless Diamond facet for ERC-1155 per-token URIs with an optional base URI.
/// @dev Owns ONLY its own selectors: the admin setters `setURI` and `setBaseURI` (new) and `uri(uint256)`, which
///      REPLACES the base {ERC1155} variant to read per-token URI storage. It does NOT inherit the {ERC1155} facet;
///      that would re-export the base surface and collide with the standalone {ERC1155} facet in a diamond. The
///      ERC-1155 base surface comes from a separately cut {ERC1155} facet, and {DeployERC1155URIStorage} composes
///      both with a mixed Add/Replace cut. The setters are gated on `DEFAULT_ADMIN_ROLE`. Pure delegator.
/// @custom:lattice-version 0.5.0
/// @custom:lattice-source OpenZeppelin v5.6.1
contract ERC1155URIStorage is IERC1155URIStorage {
    /// @notice Returns the URI for token type `tokenId`: the base URI followed by the per-token URI when one is
    ///         set, otherwise the ERC-1155 URI template.
    /// @dev Replaces the base {ERC1155} `uri` (0x0e89341c).
    function uri(uint256 tokenId) public view virtual returns (string memory) {
        return ERC1155URIStorageLib.uri(tokenId);
    }

    /// @inheritdoc IERC1155URIStorage
    function setURI(uint256 tokenId, string calldata tokenURI) public virtual {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC1155URIStorageLib._setURI(tokenId, tokenURI);
    }

    /// @inheritdoc IERC1155URIStorage
    function setBaseURI(string calldata baseURI) public virtual {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC1155URIStorageLib._setBaseURI(baseURI);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC1155URIStorage methodIdentifiers` (alphabetical by signature); kept in exact parity
    ///      by ExportSelectorsParityTest. Chunks:
    ///      `setBaseURI(string)` 0x55f804b3
    ///      `setURI(uint256,string)` 0x862440e2
    ///      `uri(uint256)` 0x0e89341c
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"55f804b3862440e20e89341c";
    }
}
