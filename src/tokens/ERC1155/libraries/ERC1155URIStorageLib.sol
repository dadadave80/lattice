// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC1155} from "@lattice/interfaces/tokens/IERC1155.sol";
import {ERC1155Lib} from "@lattice/tokens/ERC1155/libraries/ERC1155Lib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC1155URIStorage")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC1155URISTORAGE_STORAGE_SLOT = 0x410b28ad7d410d71a721debe93a5796847f0aba6b82f9b5e65108eff17bfbc00;

/// @dev 0xd3dc4451 is `type(IERC1155URIStorage).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xd3dc4451), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC1155URISTORAGE_SLOT =
    0xd822e48b513c28ab47f256a8e46baad1ce902e38e6cae6a58b04347a1a191de1;

/// @notice Storage struct for the ERC-1155 URI storage module.
/// @custom:storage-location erc7201:lattice.storage.ERC1155URIStorage
struct ERC1155URIStorageStorage {
    string _baseURI;
    mapping(uint256 tokenId => string) _tokenURIs;
}

/// @title ERC1155URIStorageLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol)
/// @notice Library implementing per-token URI storage for ERC-1155 tokens, with an optional base URI.
/// @dev Composed with {ERC1155Lib}: a token without a per-token URI falls back to the ERC-1155 URI template.
///      All state lives in its own ERC-7201 slot.
library ERC1155URIStorageLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function erc1155URIStorageStorage() internal pure returns (ERC1155URIStorageStorage storage $) {
        assembly {
            $.slot := ERC1155URISTORAGE_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the ERC-1155 URI storage module: registers IERC1155URIStorage via ERC-165.
    /// @dev Must be called inside a pre/postInitializer block. The base URI starts empty, as in OpenZeppelin.
    function __ERC1155URIStorage_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IERC1155URIStorage interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC1155URISTORAGE_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the URI for token type `tokenId`.
    /// @dev If a per-token URI is set, returns the base URI followed by it (the base URI is empty by default).
    ///      Otherwise returns {ERC1155Lib.uri}, the ERC-1155 URI template, which is empty if never set.
    function uri(uint256 tokenId) internal view returns (string memory) {
        ERC1155URIStorageStorage storage $ = erc1155URIStorageStorage();
        string memory tokenURI = $._tokenURIs[tokenId];
        return bytes(tokenURI).length > 0 ? string.concat($._baseURI, tokenURI) : ERC1155Lib.uri(tokenId);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets `tokenURI` as the per-token URI of `tokenId` and emits {IERC1155.URI} with the resolved
    ///         `uri(tokenId)`.
    function _setURI(uint256 tokenId, string memory tokenURI) internal {
        erc1155URIStorageStorage()._tokenURIs[tokenId] = tokenURI;
        emit IERC1155.URI(uri(tokenId), tokenId);
    }

    /// @notice Sets `baseURI` as the prefix of every non-empty per-token URI.
    function _setBaseURI(string memory baseURI) internal {
        erc1155URIStorageStorage()._baseURI = baseURI;
    }
}
