// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";

/// @title VotesInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Seeds the standalone Votes module and registers IVotes.
/// @dev Run through the diamond initialization window. ERC20Votes compositions must initialize ERC20,
///      EIP712, Nonces and Votes in the same call; seed AccessControl before governance roles. This step
///      supplies no token accounting or signing domain of its own.
contract VotesInit {
    function init() external {
        VotesLib.__Votes_init();
    }
}
