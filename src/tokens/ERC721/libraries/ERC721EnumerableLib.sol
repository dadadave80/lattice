// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC721} from "@lattice/interfaces/tokens/IERC721.sol";
import {IERC721Enumerable} from "@lattice/interfaces/tokens/IERC721Enumerable.sol";
import {ERC721Lib} from "@lattice/tokens/ERC721/libraries/ERC721Lib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC721Enumerable")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC721ENUMERABLE_STORAGE_SLOT = 0xf44b1a2ac6259907d34f22f5cc88909b4db34b47d9193d82fe8ed2889ec8e200;

/// @dev 0x780e9d63 is `type(IERC721Enumerable).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x780e9d63), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC721ENUMERABLE_SLOT = 0x9fad85d457c138ef818380b4b39b6b747ee53391250a17c4834c66e238e37af4;

/// @notice Storage struct for the ERC-721 enumeration extension.
/// @custom:storage-location erc7201:lattice.storage.ERC721Enumerable
struct ERC721EnumerableStorage {
    mapping(address owner => mapping(uint256 index => uint256)) _ownedTokens;
    mapping(uint256 tokenId => uint256) _ownedTokensIndex;
    uint256[] _allTokens;
    mapping(uint256 tokenId => uint256) _allTokensIndex;
}

/// @title ERC721EnumerableLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721Enumerable.sol)
/// @notice Library implementing the EIP-721 enumeration extension: every token id, and each owner's ids, in O(1)
///         swap-and-pop lists. All logic lives here; the facet delegates.
/// @dev The base {ERC721Lib} has no hook (D25, option (a)), so enumeration stays correct only while every token
///      movement goes through {_update} here. The {ERC721Enumerable} facet replaces the base transfer selectors to do
///      that. Any other code that moves a token on an enumerable diamond (a mint, a burn, or an authorization-free
///      transfer) must call this library's {_mint}, {_safeMint}, {_burn}, {_transfer}, {_safeTransfer} or {_update},
///      never {ERC721Lib}'s. {ERC721Burnable} and {ERC721Wrapper} call {ERC721Lib} directly, so they are mutually
///      exclusive with this extension. The CCTPHookReceipt example also mints through {ERC721Lib._mint}; it is a
///      standalone contract that cannot take this facet, and a fork of it that adds enumeration must mint here.
///      Differences from OpenZeppelin v5.6.1:
///      - OpenZeppelin overrides `_update`, so every internal path (`_mint`, `_burn`, `_transfer`, `_safeTransfer`)
///        is enumerated automatically. Here only this library's wrappers are: {ERC721Lib._transfer} and the other
///        {ERC721Lib} internals skip the lists.
///      - OpenZeppelin overrides `_increaseBalance` to revert `ERC721EnumerableForbiddenBatchMint`. Lattice ships no
///        batch-mint path (no ERC721Consecutive), so there is no override and no such error.
///      - The enumeration lists start empty when the extension is initialized. Cut it into a fresh diamond: on a
///        diamond that already holds tokens it would not list them.
library ERC721EnumerableLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function erc721EnumerableStorage() internal pure returns (ERC721EnumerableStorage storage $) {
        assembly {
            $.slot := ERC721ENUMERABLE_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IERC721Enumerable interface for ERC-165 discovery.
    /// @dev Must be called inside a pre/postInitializer block. The lists start empty, so there is nothing to seed.
    function __ERC721Enumerable_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    /// @notice Registers support for the IERC721Enumerable interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC721ENUMERABLE_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The number of tokens in existence.
    function totalSupply() internal view returns (uint256) {
        return erc721EnumerableStorage()._allTokens.length;
    }

    /// @notice The id at `index` of `owner`'s tokens. Reverts {IERC721Enumerable.ERC721OutOfBoundsIndex} when
    ///         `index` is past the owner's balance, and {IERC721.ERC721InvalidOwner} for a zero `owner`.
    function tokenOfOwnerByIndex(address owner, uint256 index) internal view returns (uint256) {
        if (index >= ERC721Lib.balanceOf(owner)) revert IERC721Enumerable.ERC721OutOfBoundsIndex(owner, index);
        return erc721EnumerableStorage()._ownedTokens[owner][index];
    }

    /// @notice The id at `index` of all tokens. Reverts {IERC721Enumerable.ERC721OutOfBoundsIndex} with a zero
    ///         owner when `index` is past {totalSupply}.
    function tokenByIndex(uint256 index) internal view returns (uint256) {
        if (index >= totalSupply()) revert IERC721Enumerable.ERC721OutOfBoundsIndex(address(0), index);
        return erc721EnumerableStorage()._allTokens[index];
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           MOVEMENT OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice {ERC721Lib.transferFrom} with enumeration bookkeeping.
    function transferFrom(address from, address to, uint256 tokenId) internal {
        if (to == address(0)) revert IERC721.ERC721InvalidReceiver(address(0));
        address previousOwner = _update(to, tokenId, msg.sender);
        if (previousOwner != from) revert IERC721.ERC721IncorrectOwner(from, tokenId, previousOwner);
    }

    /// @notice {ERC721Lib.safeTransferFrom} with enumeration bookkeeping.
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) internal {
        transferFrom(from, to, tokenId);
        ERC721Lib._checkOnERC721Received(msg.sender, from, to, tokenId, data);
    }

    /// @notice {ERC721Lib._mint} with enumeration bookkeeping.
    function _mint(address to, uint256 tokenId) internal {
        if (to == address(0)) revert IERC721.ERC721InvalidReceiver(address(0));
        address previousOwner = _update(to, tokenId, address(0));
        if (previousOwner != address(0)) revert IERC721.ERC721InvalidSender(address(0));
    }

    /// @notice {ERC721Lib._safeMint} with enumeration bookkeeping.
    function _safeMint(address to, uint256 tokenId, bytes memory data) internal {
        _mint(to, tokenId);
        ERC721Lib._checkOnERC721Received(msg.sender, address(0), to, tokenId, data);
    }

    /// @notice {ERC721Lib._burn} with enumeration bookkeeping.
    function _burn(uint256 tokenId) internal {
        address previousOwner = _update(address(0), tokenId, address(0));
        if (previousOwner == address(0)) revert IERC721.ERC721NonexistentToken(tokenId);
    }

    /// @notice {ERC721Lib._transfer} with enumeration bookkeeping: moves `tokenId` without an authorization check, for
    ///         permissioned or signature-based transfer paths.
    function _transfer(address from, address to, uint256 tokenId) internal {
        if (to == address(0)) revert IERC721.ERC721InvalidReceiver(address(0));
        address previousOwner = _update(to, tokenId, address(0));
        if (previousOwner == address(0)) {
            revert IERC721.ERC721NonexistentToken(tokenId);
        } else if (previousOwner != from) {
            revert IERC721.ERC721IncorrectOwner(from, tokenId, previousOwner);
        }
    }

    /// @notice {ERC721Lib._safeTransfer} with enumeration bookkeeping. The receiver sees `msg.sender` as `operator`.
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal {
        _transfer(from, to, tokenId);
        ERC721Lib._checkOnERC721Received(msg.sender, from, to, tokenId, data);
    }

    /// @notice {ERC721Lib._update} followed by OpenZeppelin's enumeration bookkeeping. Returns the previous owner.
    /// @dev Runs after the base update, so `_balances` already holds the post-move balances the list indices use.
    function _update(address to, uint256 tokenId, address auth) internal returns (address previousOwner) {
        previousOwner = ERC721Lib._update(to, tokenId, auth);

        if (previousOwner == address(0)) {
            _addTokenToAllTokensEnumeration(tokenId);
        } else if (previousOwner != to) {
            _removeTokenFromOwnerEnumeration(previousOwner, tokenId);
        }
        if (to == address(0)) {
            _removeTokenFromAllTokensEnumeration(tokenId);
        } else if (previousOwner != to) {
            _addTokenToOwnerEnumeration(to, tokenId);
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            PRIVATE HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Appends `tokenId` to `to`'s list. `to`'s balance already counts it, so its slot is `balance - 1`.
    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        ERC721EnumerableStorage storage $ = erc721EnumerableStorage();
        uint256 length = ERC721Lib.erc721Storage()._balances[to] - 1;
        $._ownedTokens[to][length] = tokenId;
        $._ownedTokensIndex[tokenId] = length;
    }

    /// @dev Appends `tokenId` to the global list.
    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        ERC721EnumerableStorage storage $ = erc721EnumerableStorage();
        $._allTokensIndex[tokenId] = $._allTokens.length;
        $._allTokens.push(tokenId);
    }

    /// @dev Swap-and-pop `tokenId` out of `from`'s list. `from`'s balance already excludes it, so the balance is
    ///      the index of the last entry. `_ownedTokensIndex[tokenId]` is cleared here and rewritten by the add.
    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        ERC721EnumerableStorage storage $ = erc721EnumerableStorage();
        uint256 lastTokenIndex = ERC721Lib.erc721Storage()._balances[from];
        uint256 tokenIndex = $._ownedTokensIndex[tokenId];

        mapping(uint256 index => uint256) storage ownedTokensByOwner = $._ownedTokens[from];

        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = ownedTokensByOwner[lastTokenIndex];
            ownedTokensByOwner[tokenIndex] = lastTokenId;
            $._ownedTokensIndex[lastTokenId] = tokenIndex;
        }

        delete $._ownedTokensIndex[tokenId];
        delete ownedTokensByOwner[lastTokenIndex];
    }

    /// @dev Swap-and-pop `tokenId` out of the global list. Like OpenZeppelin, it swaps even when `tokenId` is last.
    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        ERC721EnumerableStorage storage $ = erc721EnumerableStorage();
        uint256 lastTokenIndex = $._allTokens.length - 1;
        uint256 tokenIndex = $._allTokensIndex[tokenId];

        uint256 lastTokenId = $._allTokens[lastTokenIndex];

        $._allTokens[tokenIndex] = lastTokenId;
        $._allTokensIndex[lastTokenId] = tokenIndex;

        delete $._allTokensIndex[tokenId];
        $._allTokens.pop();
    }
}
