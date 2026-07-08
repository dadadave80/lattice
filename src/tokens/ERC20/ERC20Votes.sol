// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20Votes} from "@lattice/interfaces/tokens/IERC20Votes.sol";
import {ERC20VotesLib} from "@lattice/tokens/ERC20/libraries/ERC20VotesLib.sol";
import {Checkpoints} from "@lattice/utils/libraries/Checkpoints.sol";

/// @title ERC20Votes
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Votes.sol)
/// @notice Stateless Diamond facet combining ERC-20 with checkpoint-based voting power.
/// @dev Owns ONLY its own selectors — the checkpoint-updating `transfer`/`transferFrom` (which REPLACE the base
///      {ERC20} variants) plus the balance-aware `delegate`/`delegateBySig` (which REPLACE the base {Votes}
///      variants) and the OZ checkpoint accessors `numCheckpoints`/`checkpoints`. It does NOT inherit the {ERC20}
///      or {Votes} facets — doing so would re-export their selectors and collide with those standalone facets in a
///      Diamond. The ERC-20 share surface comes from a separately-cut {ERC20} facet and the ERC-5805 voting-power
///      surface (`getVotes`/`getPastVotes`/`getPastTotalSupply`/`delegates`/`clock`/`CLOCK_MODE`) from a
///      separately-cut {Votes} facet; {DeployERC20Votes} composes all three.
///
///      Callers must initialize the following modules in their initializer:
///        - ERC20Lib.__ERC20_init(name, symbol)
///        - EIP712Lib.__EIP712_init(name, version)
///        - NoncesLib.__Nonces_init()
///        - VotesLib.__Votes_init()
///        - ERC20VotesLib.__ERC20Votes_init()
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract ERC20Votes is IERC20Votes {
    //*//////////////////////////////////////////////////////////////////////////
    //                        IERC20 — TRANSFER OVERRIDES
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Transfers, updating vote checkpoints alongside balances (replaces the base transfer).
    function transfer(address to, uint256 value) public virtual returns (bool) {
        return ERC20VotesLib.transfer(to, value);
    }

    /// @notice Transfers from, updating vote checkpoints alongside balances (replaces the base transferFrom).
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        return ERC20VotesLib.transferFrom(from, to, value);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       IVOTES — DELEGATION OVERRIDES
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Delegates votes from the caller to `delegatee` (replaces the base {Votes} variant).
    /// @dev Uses caller's ERC-20 balance as voting units.
    function delegate(address delegatee) public virtual {
        ERC20VotesLib.delegate(delegatee);
    }

    /// @notice Delegates votes from the signer to `delegatee` via EIP-712 (replaces the base {Votes} variant).
    /// @dev Recovers signer, reads their ERC-20 balance, then delegates.
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        public
        virtual
    {
        ERC20VotesLib.delegateBySig(delegatee, nonce, expiry, v, r, s);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      CHECKPOINT ACCESSORS (OZ ERC20Votes)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the number of checkpoints for `account`.
    /// @dev Used by governance frameworks and off-chain indexers to enumerate checkpoint history.
    function numCheckpoints(address account) public view virtual returns (uint32) {
        return ERC20VotesLib.numCheckpoints(account);
    }

    /// @notice Returns the checkpoint at position `pos` for `account` (0-indexed).
    /// @dev Used by governance frameworks and off-chain indexers to enumerate checkpoint history.
    function checkpoints(address account, uint32 pos) public view virtual returns (Checkpoints.Checkpoint208 memory) {
        return ERC20VotesLib.checkpoints(account, pos);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC20Votes methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `checkpoints(address,uint32)` 0xf1127ed8
    ///      `delegate(address)` 0x5c19a95c
    ///      `delegateBySig(address,uint256,uint256,uint8,bytes32,bytes32)` 0xc3cda520
    ///      `numCheckpoints(address)` 0x6fcfff45
    ///      `transfer(address,uint256)` 0xa9059cbb
    ///      `transferFrom(address,address,uint256)` 0x23b872dd
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"f1127ed85c19a95cc3cda5206fcfff45a9059cbb23b872dd";
    }
}
