// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";
import {IERC721} from "@lattice/interfaces/tokens/IERC721.sol";
import {ERC721Lib} from "@lattice/tokens/ERC721/libraries/ERC721Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";

/// @title ERC721VotesLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721Votes.sol)
/// @notice Library adding ERC-5805 voting power to ERC-721, where each token is one voting unit.
/// @dev No own storage, init or ERC-165 id: it moves voting units in {VotesLib} (which registers IVotes) as
///      {ERC721Lib} moves tokens. The base {ERC721Lib} has no hook (D25, option (a)), so voting power stays correct
///      only while every token movement goes through {_update} here. The {ERC721Votes} facet replaces the base
///      transfer selectors to do that. Any other code that moves a token on a votes diamond (a mint, a burn, or an
///      authorization-free transfer) must call this library's {_mint}, {_safeMint}, {_burn}, {_transfer},
///      {_safeTransfer} or {_update}, never {ERC721Lib}'s. {ERC721Burnable} and {ERC721Wrapper} call {ERC721Lib}
///      directly, so they are mutually exclusive with this extension. The CCTPHookReceipt example also mints through
///      {ERC721Lib._mint}; it is a standalone contract that cannot take this facet, and a fork of it that adds
///      votes must mint here.
///      Differences from OpenZeppelin v5.6.1:
///      - OpenZeppelin overrides `_update`, so every internal path (`_mint`, `_burn`, `_transfer`, `_safeTransfer`)
///        moves voting units automatically. Here only this library's wrappers do: {ERC721Lib._transfer} and the
///        other {ERC721Lib} internals move no units.
///      - OpenZeppelin overrides `_increaseBalance` to move batch-minted units. Lattice ships no batch-mint path (no
///        ERC721Consecutive), so there is no override.
///      - Voting units are read from the ERC-721 balance by {delegate} and {delegateBySig}, which replace the base
///        {Votes} facet's ERC-20-balance versions; OpenZeppelin overrides `_getVotingUnits` instead.
library ERC721VotesLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                           MOVEMENT OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice {ERC721Lib.transferFrom} that also moves one voting unit.
    function transferFrom(address from, address to, uint256 tokenId) internal {
        if (to == address(0)) revert IERC721.ERC721InvalidReceiver(address(0));
        address previousOwner = _update(to, tokenId, msg.sender);
        if (previousOwner != from) revert IERC721.ERC721IncorrectOwner(from, tokenId, previousOwner);
    }

    /// @notice {ERC721Lib.safeTransferFrom} that also moves one voting unit.
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) internal {
        transferFrom(from, to, tokenId);
        ERC721Lib._checkOnERC721Received(msg.sender, from, to, tokenId, data);
    }

    /// @notice {ERC721Lib._mint} that also mints one voting unit.
    function _mint(address to, uint256 tokenId) internal {
        if (to == address(0)) revert IERC721.ERC721InvalidReceiver(address(0));
        address previousOwner = _update(to, tokenId, address(0));
        if (previousOwner != address(0)) revert IERC721.ERC721InvalidSender(address(0));
    }

    /// @notice {ERC721Lib._safeMint} that also mints one voting unit.
    function _safeMint(address to, uint256 tokenId, bytes memory data) internal {
        _mint(to, tokenId);
        ERC721Lib._checkOnERC721Received(msg.sender, address(0), to, tokenId, data);
    }

    /// @notice {ERC721Lib._burn} that also burns one voting unit.
    function _burn(uint256 tokenId) internal {
        address previousOwner = _update(address(0), tokenId, address(0));
        if (previousOwner == address(0)) revert IERC721.ERC721NonexistentToken(tokenId);
    }

    /// @notice {ERC721Lib._transfer} that also moves one voting unit: moves `tokenId` without an authorization check, for
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

    /// @notice {ERC721Lib._safeTransfer} that also moves one voting unit. The receiver sees `msg.sender` as `operator`.
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal {
        _transfer(from, to, tokenId);
        ERC721Lib._checkOnERC721Received(msg.sender, from, to, tokenId, data);
    }

    /// @notice {ERC721Lib._update} followed by OpenZeppelin's `_transferVotingUnits(previousOwner, to, 1)`.
    /// @dev Like OpenZeppelin, it moves the unit before the caller checks the previous owner; every caller here
    ///      reverts on a bad previous owner, which undoes the move.
    function _update(address to, uint256 tokenId, address auth) internal returns (address previousOwner) {
        previousOwner = ERC721Lib._update(to, tokenId, auth);
        VotesLib._transferVotingUnits(previousOwner, to, 1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         DELEGATION (BALANCE-AWARE)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Delegates the caller's votes to `delegatee`, using the caller's ERC-721 balance as voting units.
    function delegate(address delegatee) internal {
        VotesLib.delegate(delegatee, _getVotingUnits(msg.sender));
    }

    /// @notice Delegates by EIP-712 signature, using the signer's ERC-721 balance as voting units.
    /// @dev Recovers the signer first to read its balance, then consumes the nonce and delegates, as
    ///      {ERC20VotesLib.delegateBySig} does. Keep the nonce handling in step with {VotesLib.delegateBySig}.
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) internal {
        address signer = VotesLib._recoverDelegationSigner(delegatee, nonce, expiry, v, r, s);
        uint256 units = _getVotingUnits(signer);
        NoncesLib.useCheckedNonce(signer, nonce);
        VotesLib._delegate(signer, delegatee, units);
    }

    /// @notice The voting units of `account`: its ERC-721 balance.
    function _getVotingUnits(address account) internal view returns (uint256) {
        return ERC721Lib.erc721Storage()._balances[account];
    }
}
