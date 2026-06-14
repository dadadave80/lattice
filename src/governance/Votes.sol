// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";
import {IVotes} from "@lattice/interfaces/IVotes.sol";
import {ERC20Lib} from "@lattice/tokens/libraries/ERC20Lib.sol";

/// @title Votes
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/utils/Votes.sol)
/// @notice Stateless Diamond facet implementing ERC-5805 delegation + ERC-6372 clock.
/// @dev All logic lives in VotesLib. This contract is a pure delegator.
///      When used standalone, voting units default to 0 (no token balance).
///      Use ERC20Votes instead to combine ERC-20 balances with voting power.
contract Votes is IVotes {
    /// @inheritdoc IVotes
    function getVotes(address account) public view virtual returns (uint256) {
        return VotesLib.getVotes(account);
    }

    /// @inheritdoc IVotes
    function getPastVotes(address account, uint256 timepoint) public view virtual returns (uint256) {
        return VotesLib.getPastVotes(account, timepoint);
    }

    /// @inheritdoc IVotes
    function getPastTotalSupply(uint256 timepoint) public view virtual returns (uint256) {
        return VotesLib.getPastTotalSupply(timepoint);
    }

    /// @inheritdoc IVotes
    function delegates(address account) public view virtual returns (address) {
        return VotesLib.delegates(account);
    }

    /// @inheritdoc IVotes
    function delegate(address delegatee) public virtual {
        VotesLib.delegate(delegatee, ERC20Lib.balanceOf(msg.sender));
    }

    /// @inheritdoc IVotes
    /// @dev WARNING (VOT-08): The base Votes facet passes 0 voting units. This means the nonce
    ///      is consumed and DelegateChanged is emitted, but vote checkpoints are NOT updated.
    ///      Token-bearing facets (e.g. ERC20Votes) MUST override this function to pass the
    ///      signer's actual balance as voting units. Using this base implementation in a
    ///      token context will silently leave voting power at zero after delegation.
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        public
        virtual
    {
        VotesLib.delegateBySig(delegatee, nonce, expiry, v, r, s, 0);
    }

    /// @inheritdoc IVotes
    function clock() public view virtual returns (uint48) {
        return VotesLib.clock();
    }

    /// @inheritdoc IVotes
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual returns (string memory) {
        return VotesLib.CLOCK_MODE();
    }
}
