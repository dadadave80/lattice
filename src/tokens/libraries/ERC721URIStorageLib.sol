// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {ERC721Lib} from "@lattice/tokens/libraries/ERC721Lib.sol";
import {IERC721URIStorage} from "@lattice/interfaces/IERC721URIStorage.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC721URIStorage")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC721URISTORAGE_STORAGE_SLOT =
    0xcad0a180da252dc6d7fda719c706c048d7fcfbea8301125fec9b8527feaa7700;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC721URISTORAGE_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x49064906 is the ERC-4906 (MetadataUpdate) interface ID.
/// `keccak256(abi.encode(bytes4(0x49064906), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ERC4906_SLOT = 0xf6e2df7ae707ae7f293659ac6f748c7ba27a30d8639e53e763363aebc5fa8f65;

/// @notice Storage struct for ERC-721URIStorage module.
/// @custom:storage-location erc7201:lattice.storage.ERC721URIStorage
struct ERC721URIStorageStorage {
    mapping(uint256 tokenId => string) _tokenURIs;
}

/// @title ERC721URIStorageLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library implementing per-token URI storage for ERC-721 tokens (EIP-4906).
/// @dev Designed to be composed with ERC721Lib. All state lives in an ERC-7201 slot.
library ERC721URIStorageLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function erc721URIStorageStorage() internal pure returns (ERC721URIStorageStorage storage $) {
        assembly {
            $.slot := ERC721URISTORAGE_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the ERC-721URIStorage module.
    /// @dev Must be called inside a pre/postInitializer block.
    ///      Registers the ERC-4906 interface ID.
    function __ERC721URIStorage_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the ERC-4906 interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ERC4906_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the URI for `tokenId`.
    /// @dev If a per-token URI is set, returns `_baseURI() + uri`.
    ///      Falls back to the base ERC721 tokenURI (base + tokenId) if no per-token URI is set.
    function tokenURI(uint256 tokenId) internal view returns (string memory) {
        string memory _tokenURI = erc721URIStorageStorage()._tokenURIs[tokenId];
        string memory base = ERC721Lib._baseURI();

        if (bytes(_tokenURI).length == 0) {
            // No per-token URI: fall back to base ERC721 tokenURI.
            return ERC721Lib.tokenURI(tokenId);
        }

        if (bytes(base).length == 0) {
            return _tokenURI;
        }

        return string(abi.encodePacked(base, _tokenURI));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets the token URI for `tokenId` and emits MetadataUpdate.
    function _setTokenURI(uint256 tokenId, string memory uri) internal {
        erc721URIStorageStorage()._tokenURIs[tokenId] = uri;
        emit IERC721URIStorage.MetadataUpdate(tokenId);
    }
}
