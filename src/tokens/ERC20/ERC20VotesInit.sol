// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";
import {ERC20VotesLib} from "@lattice/tokens/ERC20/libraries/ERC20VotesLib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";

/// @title ERC20VotesInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ERC-20 Votes extension recipe — seeds the EIP-712 domain (name `name_`,
///         version "1") and nonce storage the `delegateBySig` digest reads, the checkpoint/clock state (registering
///         IVotes and IERC20Votes), and grants `admin_` the DEFAULT_ADMIN_ROLE that gates a consumer's minting
///         authority. Delegatecalled by {Diamond.initialize} (through {MultiInit}) inside the initializing window
///         opened by the diamond, alongside the base {ERC20Init}; it must NOT open its own pre/postInitializer.
contract ERC20VotesInit {
    function init(string memory name_, address admin_) external {
        EIP712Lib.__EIP712_init(name_, "1");
        NoncesLib.__Nonces_init();
        VotesLib.__Votes_init();
        ERC20VotesLib.__ERC20Votes_init();
        AccessControlLib.__AccessControl_init(admin_);
    }
}
