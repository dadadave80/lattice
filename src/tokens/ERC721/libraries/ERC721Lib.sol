// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC721, IERC721Receiver} from "@lattice/interfaces/tokens/IERC721.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC721")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC721_STORAGE_SLOT = 0xb57056eaff39f17dbb7656e3d0f4bee059cc8b05a6894f946db4b85f3b03e700;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC721_ERC165_STORAGE_LOCATION = 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x80ac58cd is `type(IERC721).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x80ac58cd), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC721_SLOT = 0x741e8246930c2bfc93c4e7042569e8d7f42e535e31e366398006f597e42d38fb;

/// @dev 0x5b5e139f is `type(IERC721Metadata).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x5b5e139f), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC721METADATA_SLOT = 0xdec0fb77ff71ebf00e30e78bd255149ae2525d6ff9925bff1ddd9a569813231d;

/// @notice Storage struct for ERC-721 module.
/// @custom:storage-location erc7201:lattice.storage.ERC721
struct ERC721Storage {
    mapping(uint256 tokenId => address) _owners;
    mapping(address owner => uint256) _balances;
    mapping(uint256 tokenId => address) _tokenApprovals;
    mapping(address owner => mapping(address operator => bool)) _operatorApprovals;
    string _name;
    string _symbol;
}

/// @title ERC721Lib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/ERC721.sol)
/// @notice Library implementing the ERC-721 Non-Fungible Token standard.
/// @dev Mirrors OpenZeppelin v5 ERC721 logic. All state lives in an ERC-7201 slot.
library ERC721Lib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function erc721Storage() internal pure returns (ERC721Storage storage $) {
        assembly {
            $.slot := ERC721_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the ERC-721 module with name and symbol.
    /// @dev Must be called inside a pre/postInitializer block.
    function __ERC721_init(string memory name_, string memory symbol_) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);

        ERC721Storage storage $ = erc721Storage();
        $._name = name_;
        $._symbol = symbol_;

        registerInterfaces();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for IERC721 and IERC721Metadata interfaces via ERC-165.
    function registerInterfaces() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC721_SLOT, true)
            sstore(ERC165_MAP_IERC721METADATA_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the token name.
    function name() internal view returns (string memory) {
        return erc721Storage()._name;
    }

    /// @notice Returns the token symbol.
    function symbol() internal view returns (string memory) {
        return erc721Storage()._symbol;
    }

    /// @notice Returns the number of tokens owned by `owner`.
    function balanceOf(address owner) internal view returns (uint256) {
        if (owner == address(0)) revert IERC721.ERC721InvalidOwner(address(0));
        return erc721Storage()._balances[owner];
    }

    /// @notice Returns the owner of `tokenId`. Reverts if token does not exist.
    function ownerOf(uint256 tokenId) internal view returns (address) {
        address owner = _requireOwned(tokenId);
        return owner;
    }

    /// @notice Returns the address approved for `tokenId`. Reverts if token does not exist.
    function getApproved(uint256 tokenId) internal view returns (address) {
        _requireOwned(tokenId);
        return _getApproved(tokenId);
    }

    /// @notice Returns true if `operator` is approved to manage all of `owner`'s assets.
    function isApprovedForAll(address owner, address operator) internal view returns (bool) {
        return erc721Storage()._operatorApprovals[owner][operator];
    }

    /// @notice Returns the base URI used for token URI computation.
    /// @dev Returns empty string by default. Facets may override tokenURI to supply a base.
    function _baseURI() internal pure returns (string memory) {
        return "";
    }

    /// @notice Returns the URI for `tokenId`. Concatenates _baseURI() + tokenId string if base is non-empty.
    function tokenURI(uint256 tokenId) internal view returns (string memory) {
        _requireOwned(tokenId);
        string memory base = _baseURI();
        if (bytes(base).length == 0) {
            return "";
        }
        return string(abi.encodePacked(base, _toString(tokenId)));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           MUTATION OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Approves `to` to transfer `tokenId`. Caller must be owner or approved operator.
    function approve(address to, uint256 tokenId) internal {
        address sender = msg.sender;
        address owner = _requireOwned(tokenId);
        if (sender != owner && !isApprovedForAll(owner, sender)) {
            revert IERC721.ERC721InvalidApprover(sender);
        }
        _approve(to, tokenId, owner, true);
    }

    /// @notice Enables or disables approval for `operator` to manage all of the caller's assets.
    function setApprovalForAll(address operator, bool approved) internal {
        address owner = msg.sender;
        _setApprovalForAll(owner, operator, approved);
    }

    /// @notice Transfers `tokenId` from `from` to `to` without safety checks.
    function transferFrom(address from, address to, uint256 tokenId) internal {
        if (to == address(0)) revert IERC721.ERC721InvalidReceiver(address(0));
        address previousOwner = _update(to, tokenId, msg.sender);
        if (previousOwner != from) revert IERC721.ERC721IncorrectOwner(from, tokenId, previousOwner);
    }

    /// @notice Safely transfers `tokenId` from `from` to `to` with additional `data`.
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) internal {
        transferFrom(from, to, tokenId);
        _checkOnERC721Received(msg.sender, from, to, tokenId, data);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the owner of `tokenId` without reverting (zero address if nonexistent).
    function _ownerOf(uint256 tokenId) internal view returns (address) {
        return erc721Storage()._owners[tokenId];
    }

    /// @notice Returns the approved address for `tokenId` without existence check.
    function _getApproved(uint256 tokenId) internal view returns (address) {
        return erc721Storage()._tokenApprovals[tokenId];
    }

    /// @notice Returns true if `spender` is the owner or approved for `tokenId`.
    function _isAuthorized(address owner, address spender, uint256 tokenId) internal view returns (bool) {
        return spender != address(0)
            && (owner == spender || isApprovedForAll(owner, spender) || _getApproved(tokenId) == spender);
    }

    /// @notice Reverts if `spender` is not authorized for `tokenId`.
    function _checkAuthorized(address owner, address spender, uint256 tokenId) internal view {
        if (!_isAuthorized(owner, spender, tokenId)) {
            if (owner == address(0)) {
                revert IERC721.ERC721NonexistentToken(tokenId);
            } else {
                revert IERC721.ERC721InsufficientApproval(spender, tokenId);
            }
        }
    }

    /// @notice Central state mutation. Transfers `tokenId` to `to`, authorized by `auth`.
    /// @dev If `auth` is non-zero, checks authorization. Returns previous owner.
    function _update(address to, uint256 tokenId, address auth) internal returns (address from) {
        from = _ownerOf(tokenId);

        if (auth != address(0)) {
            _checkAuthorized(from, auth, tokenId);
        }

        if (from != address(0)) {
            // Clear token approval on transfer. Pass address(0) as auth to skip authorization
            // check (no validation needed here) — matches OZ's _approve call in _update.
            _approve(address(0), tokenId, address(0), false);
            unchecked {
                erc721Storage()._balances[from] -= 1;
            }
        }

        if (to != address(0)) {
            unchecked {
                erc721Storage()._balances[to] += 1;
            }
        }

        erc721Storage()._owners[tokenId] = to;
        emit IERC721.Transfer(from, to, tokenId);
    }

    /// @notice Mints `tokenId` to `to`. Reverts if `to` is zero or token already exists.
    function _mint(address to, uint256 tokenId) internal {
        if (to == address(0)) revert IERC721.ERC721InvalidReceiver(address(0));
        address previousOwner = _update(to, tokenId, address(0));
        if (previousOwner != address(0)) revert IERC721.ERC721InvalidSender(previousOwner);
    }

    /// @notice Safely mints `tokenId` to `to`, calling receiver hook if `to` is a contract.
    function _safeMint(address to, uint256 tokenId, bytes memory data) internal {
        _mint(to, tokenId);
        _checkOnERC721Received(address(0), address(0), to, tokenId, data);
    }

    /// @notice Safely mints `tokenId` to `to` with empty data.
    function _safeMint(address to, uint256 tokenId) internal {
        _safeMint(to, tokenId, "");
    }

    /// @notice Burns `tokenId`. Reverts if token does not exist.
    function _burn(uint256 tokenId) internal {
        address previousOwner = _update(address(0), tokenId, address(0));
        if (previousOwner == address(0)) revert IERC721.ERC721NonexistentToken(tokenId);
    }

    /// @notice Approves `to` for `tokenId`. Optionally emits Approval event.
    /// @dev Guard matches OZ: enter owner-lookup block only when emitEvent OR auth != address(0).
    ///      Uses _requireOwned (reverting) rather than _ownerOf to catch nonexistent tokens.
    function _approve(address to, uint256 tokenId, address auth, bool emitEvent) internal {
        if (emitEvent || auth != address(0)) {
            address owner = _requireOwned(tokenId);
            if (auth != address(0) && owner != auth && !isApprovedForAll(owner, auth)) {
                revert IERC721.ERC721InvalidApprover(auth);
            }
            if (emitEvent) {
                emit IERC721.Approval(owner, to, tokenId);
            }
        }
        erc721Storage()._tokenApprovals[tokenId] = to;
    }

    /// @notice Sets or unsets the approval of `operator` by `owner`.
    function _setApprovalForAll(address owner, address operator, bool approved) internal {
        if (operator == address(0)) revert IERC721.ERC721InvalidOperator(operator);
        erc721Storage()._operatorApprovals[owner][operator] = approved;
        emit IERC721.ApprovalForAll(owner, operator, approved);
    }

    /// @notice Increases the balance of `account` by `value` without minting a tracked token.
    /// @dev Extension hook for ERC721Consecutive and similar patterns that synthesize ownership
    ///      outside of the normal _owners mapping. Matches OZ's _increaseBalance.
    function _increaseBalance(address account, uint128 value) internal {
        unchecked {
            erc721Storage()._balances[account] += value;
        }
    }

    /// @notice Transfers `tokenId` from `from` to `to` bypassing msg.sender authorization.
    /// @dev For permissioned or signature-based transfer mechanisms. Validates previous owner.
    function _transfer(address from, address to, uint256 tokenId) internal {
        if (to == address(0)) revert IERC721.ERC721InvalidReceiver(address(0));
        address previousOwner = _update(to, tokenId, address(0));
        if (previousOwner != from) revert IERC721.ERC721IncorrectOwner(from, tokenId, previousOwner);
    }

    /// @notice Safely transfers `tokenId` from `from` to `to` with `data`, bypassing authorization.
    /// @dev Calls receiver hook if `to` is a contract.
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal {
        _transfer(from, to, tokenId);
        _checkOnERC721Received(address(0), from, to, tokenId, data);
    }

    /// @notice Reverts if `tokenId` does not exist. Returns the owner.
    function _requireOwned(uint256 tokenId) internal view returns (address) {
        address owner = _ownerOf(tokenId);
        if (owner == address(0)) revert IERC721.ERC721NonexistentToken(tokenId);
        return owner;
    }

    /// @notice Calls IERC721Receiver.onERC721Received if `to` is a contract.
    /// @dev Distinguishes between a non-implementor (empty revert) and a deliberate
    ///      revert from the receiver (non-empty reason). Non-empty reasons are re-bubbled
    ///      verbatim so callers see the actual error from the receiver contract.
    function _checkOnERC721Received(address operator, address from, address to, uint256 tokenId, bytes memory data)
        internal
    {
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(operator, from, tokenId, data) returns (bytes4 retval) {
                if (retval != IERC721Receiver.onERC721Received.selector) {
                    revert IERC721.ERC721InvalidReceiver(to);
                }
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert IERC721.ERC721InvalidReceiver(to);
                } else {
                    assembly ("memory-safe") {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            STRING UTILITY
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Converts a uint256 to its decimal string representation.
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
