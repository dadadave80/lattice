// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Votes} from "@lattice/governance/Votes.sol";
import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";
import {IERC20} from "@lattice/interfaces/IERC20.sol";
import {IVotes} from "@lattice/interfaces/IVotes.sol";
import {ERC20} from "@lattice/tokens/ERC20.sol";
import {ERC20Lib} from "@lattice/tokens/libraries/ERC20Lib.sol";
import {ERC20VotesLib} from "@lattice/tokens/libraries/ERC20VotesLib.sol";
import {Checkpoints} from "@lattice/utils/libraries/Checkpoints.sol";

/// @title ERC20Votes
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Votes.sol)
/// @notice Stateless Diamond facet combining ERC-20 with checkpoint-based voting power.
/// @dev Inherits ERC20 (delegates IERC20 calls to ERC20Lib) and Votes (delegates IVotes calls
///      to VotesLib). Overrides transfer/transferFrom/delegate/delegateBySig to route through
///      ERC20VotesLib, which updates both ERC-20 balances and vote checkpoints atomically.
///
///      Callers must initialize the following modules in their initializer:
///        - ERC20Lib.__ERC20_init(name, symbol)
///        - EIP712Lib.__EIP712_init(name, version)
///        - NoncesLib.__Nonces_init()
///        - VotesLib.__Votes_init()
///        - ERC20VotesLib.__ERC20Votes_init()
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract ERC20Votes is ERC20, Votes {
    //*//////////////////////////////////////////////////////////////////////////
    //                        IERC20 — TRANSFER OVERRIDES
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IERC20
    /// @dev Routes through ERC20VotesLib to update vote checkpoints alongside balances.
    function transfer(address to, uint256 value) public override returns (bool) {
        return ERC20VotesLib.transfer(to, value);
    }

    /// @inheritdoc IERC20
    /// @dev Routes through ERC20VotesLib to update vote checkpoints alongside balances.
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        return ERC20VotesLib.transferFrom(from, to, value);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       IVOTES — DELEGATION OVERRIDES
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IVotes
    /// @dev Uses caller's ERC-20 balance as voting units.
    function delegate(address delegatee) public override {
        ERC20VotesLib.delegate(delegatee);
    }

    /// @inheritdoc IVotes
    /// @dev Recovers signer, reads their ERC-20 balance, then delegates.
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        public
        override
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
}
