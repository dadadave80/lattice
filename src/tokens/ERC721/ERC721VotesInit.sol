// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";
import {IERC721Consecutive} from "@lattice/interfaces/tokens/IERC721Consecutive.sol";
import {ERC721ConsecutiveLib} from "@lattice/tokens/ERC721/libraries/ERC721ConsecutiveLib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";

/// @title ERC721VotesInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ERC-721 Votes extension recipe — seeds the EIP-712 domain (name `name_`,
///         version "1") and nonce storage the `delegateBySig` digest reads, and the checkpoint/clock state (which
///         registers IVotes). Delegatecalled by {Diamond.initialize} (through {MultiInit}) inside the initializing
///         window opened by the diamond, alongside the base {ERC721Init}; it must NOT open its own
///         pre/postInitializer. Reverts `ERC721VotesForbiddenBatchMint` on a diamond that initialized batch minting
///         ({ERC721ConsecutiveLib}), whose batches the vote checkpoints would miss, including in a later upgrade cut.
contract ERC721VotesInit {
    function init(string memory name_) external {
        if (ERC721ConsecutiveLib.erc721ConsecutiveStorage()._enabled) {
            revert IERC721Consecutive.ERC721VotesForbiddenBatchMint();
        }
        EIP712Lib.__EIP712_init(name_, "1");
        NoncesLib.__Nonces_init();
        VotesLib.__Votes_init();
    }
}
