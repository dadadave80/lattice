// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";

/// @title Votes
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/utils/Votes.sol)
/// @notice Stateless Diamond facet implementing ERC-5805 delegation + ERC-6372 clock.
/// @dev All logic lives in VotesLib. This contract is a pure delegator.
///      When used standalone, voting units default to 0 (no token balance).
///      Use ERC20Votes instead to combine ERC-20 balances with voting power.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect Votes methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `CLOCK_MODE()` 0x4bf5d7e9
    ///      `clock()` 0x91ddadf4
    ///      `delegate(address)` 0x5c19a95c
    ///      `delegateBySig(address,uint256,uint256,uint8,bytes32,bytes32)` 0xc3cda520
    ///      `delegates(address)` 0x587cde1e
    ///      `getPastTotalSupply(uint256)` 0x8e539e8c
    ///      `getPastVotes(address,uint256)` 0x3a46b1a8
    ///      `getVotes(address)` 0x9ab24eb0
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"4bf5d7e991ddadf45c19a95cc3cda520587cde1e8e539e8c3a46b1a89ab24eb0";
    }
}
