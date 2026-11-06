// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";

/// @title VotesInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Seeds the standalone Votes module and registers IVotes.
/// @dev Run through the diamond initialization window. ERC20Votes compositions must initialize ERC20,
///      EIP712, Nonces and Votes in the same call; seed AccessControl before governance roles. This step
///      supplies no token accounting or signing domain of its own.
/// @custom:lattice-kind step
contract VotesInit {
    /// @custom:lattice-initializes Votes;
    /// @custom:lattice-after ERC20 convention balance-backed-delegation;
    /// @custom:lattice-after EIP712 convention signature-domain-configuration;
    /// @custom:lattice-after Nonces convention replay-state-registration;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-param none;
    /// @custom:lattice-registers-interfaces
    function init() external {
        VotesLib.__Votes_init();
    }
}
