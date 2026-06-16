// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";
import {IVotes} from "@lattice/interfaces/IVotes.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Minimal consumer of VotesLib that does NOT impose the ERC20Votes uint208 supply cap,
///      exercising the base library's voting-unit accounting directly. Mirrors how a custom
///      (uncapped) token built on VotesLib would move voting units.
contract MockUncappedVotes {
    function transferVotingUnits(address from, address to, uint256 amount) external {
        VotesLib._transferVotingUnits(from, to, amount);
    }
}

/// @notice Regression for the unchecked `uint208(amount)` casts in VotesLib._transferVotingUnits /
///         _moveDelegateVotes. A raw cast silently truncated amounts > type(uint208).max, corrupting
///         vote/supply checkpoints for any uncapped consumer. The cast must now revert instead.
contract VotesLibOverflowTest is Test {
    MockUncappedVotes mock;

    function setUp() public {
        mock = new MockUncappedVotes();
        vm.warp(1_000_000);
    }

    function test_TransferVotingUnitsRevertsOnUint208Overflow() public {
        uint256 tooBig = uint256(type(uint208).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(IVotes.VotesOverflowedVotingUnits.selector, tooBig));
        mock.transferVotingUnits(address(0), address(0xBEEF), tooBig);
    }

    function test_TransferVotingUnitsAcceptsUint208Max() public {
        // Boundary: exactly type(uint208).max fits and must not revert.
        mock.transferVotingUnits(address(0), address(0xBEEF), uint256(type(uint208).max));
    }
}
