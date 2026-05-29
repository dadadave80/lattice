// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";
import {ERC20Lib} from "@lattice/tokens/libraries/ERC20Lib.sol";
import {IVotes} from "@lattice/interfaces/IVotes.sol";

/// @title Votes
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
        VotesLib.delegate(delegatee, ERC20Lib.balanceOf(ContextLib.msgSender()));
    }

    /// @inheritdoc IVotes
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        public
        virtual
    {
        // The signer's voting units are read after signature verification inside VotesLib;
        // we pass 0 here as a placeholder — ERC20Votes overrides this with the actual balance.
        // For the base Votes facet, use the standard pattern: sig recovery + delegate.
        // Actual balance is fetched after sig recovery — we rely on ERC20Votes override.
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
