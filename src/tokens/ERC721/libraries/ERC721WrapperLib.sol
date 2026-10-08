// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC721, IERC721Receiver} from "@lattice/interfaces/tokens/IERC721.sol";
import {IERC721Wrapper} from "@lattice/interfaces/tokens/IERC721Wrapper.sol";
import {ERC721Lib} from "@lattice/tokens/ERC721/libraries/ERC721Lib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC721Wrapper")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC721WRAPPER_STORAGE_SLOT = 0x434ed71ac956f35c738c07eaadcb4935b3686524cef619db6f8caec66db4f500;

/// @dev 0xd9e5011d is `type(IERC721Wrapper).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xd9e5011d), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC721WRAPPER_SLOT = 0x77282127b26cc01e57f32ac10fe9c172e5d41d192d3e6e87d2e5c74c35c6f9e8;

/// @notice Storage struct for the ERC-721 wrapper.
/// @custom:storage-location erc7201:lattice.storage.ERC721Wrapper
struct ERC721WrapperStorage {
    address _underlying;
}

/// @title ERC721WrapperLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721Wrapper.sol)
/// @notice Library implementing id-for-id wrapping of an underlying ERC-721. All logic lives here; the facet delegates.
/// @dev OpenZeppelin keeps the underlying in an `immutable`; a diamond's facets are shared, so this stores it in the
///      ERC-7201 slot instead. The underlying is trusted, as upstream assumes: {depositFor} calls it before minting.
///      Mints and burns go straight through {ERC721Lib}, so an extension that observes movement by `Replace`-ing the
///      base transfer selectors would not see them, and the two are mutually exclusive (D25, #234).
library ERC721WrapperLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function erc721WrapperStorage() internal pure returns (ERC721WrapperStorage storage $) {
        assembly {
            $.slot := ERC721WRAPPER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the wrapper with its underlying collection.
    /// @dev Must be called inside a pre/postInitializer block. Like OpenZeppelin, it does not validate `underlying_`.
    function __ERC721Wrapper_init(address underlying_) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        erc721WrapperStorage()._underlying = underlying_;
        registerInterface();
    }

    /// @notice Registers support for the IERC721Wrapper interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC721WRAPPER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The underlying ERC-721 collection being wrapped.
    function underlying() internal view returns (address) {
        return erc721WrapperStorage()._underlying;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            WRAP / UNWRAP
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Pulls each of `tokenIds` from the caller's underlying balance and safely mints the same id to `account`.
    /// @dev The pull is an unsafe `transferFrom`, so it triggers no receiver hook (and so no {onERC721Received}).
    function depositFor(address account, uint256[] memory tokenIds) internal returns (bool) {
        IERC721 underlying_ = IERC721(underlying());
        uint256 length = tokenIds.length;
        for (uint256 i; i < length; ++i) {
            uint256 tokenId = tokenIds[i];
            underlying_.transferFrom(msg.sender, address(this), tokenId);
            ERC721Lib._safeMint(account, tokenId);
        }
        return true;
    }

    /// @notice Burns each of `tokenIds` (the caller must own or be approved for it) and safely sends the same
    ///         underlying id to `account`.
    /// @dev A non-zero `auth` makes {ERC721Lib._update} check authorization and existence, so the previous owner
    ///      needs no check. The wrapped id is gone before the external call, so the call cannot reuse it.
    function withdrawTo(address account, uint256[] memory tokenIds) internal returns (bool) {
        IERC721 underlying_ = IERC721(underlying());
        uint256 length = tokenIds.length;
        for (uint256 i; i < length; ++i) {
            uint256 tokenId = tokenIds[i];
            ERC721Lib._update(address(0), tokenId, msg.sender);
            underlying_.safeTransferFrom(address(this), account, tokenId);
        }
        return true;
    }

    /// @notice Mints the wrapped id to `from` when the underlying collection safely transfers a token to the diamond.
    /// @dev Reverts {IERC721Wrapper.ERC721UnsupportedToken} for any caller other than the underlying. Like
    ///      OpenZeppelin, it ignores `data`. A plain `transferFrom` skips this hook; {recover} covers that case.
    function onERC721Received(address, address from, uint256 tokenId, bytes memory) internal returns (bytes4) {
        if (msg.sender != underlying()) revert IERC721Wrapper.ERC721UnsupportedToken(msg.sender);
        ERC721Lib._safeMint(from, tokenId);
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @notice Mints the wrapped `tokenId` to `account` for an underlying token the diamond holds unwrapped (sent by a
    ///         plain `transferFrom`).
    /// @dev Internal — a facet exposing this MUST add access control. Not on the base {ERC721Wrapper} facet.
    ///      Reverts {IERC721.ERC721IncorrectOwner} when the diamond does not own the underlying `tokenId`.
    function recover(address account, uint256 tokenId) internal returns (uint256) {
        address owner = IERC721(underlying()).ownerOf(tokenId);
        if (owner != address(this)) revert IERC721.ERC721IncorrectOwner(address(this), tokenId, owner);
        ERC721Lib._safeMint(account, tokenId);
        return tokenId;
    }
}
