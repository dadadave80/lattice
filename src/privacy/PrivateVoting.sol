// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPrivateVoting} from "@lattice/interfaces/privacy/IPrivateVoting.sol";
import {ISemaphore} from "@lattice/interfaces/privacy/ISemaphore.sol";
import {PrivateVotingLib} from "@lattice/privacy/libraries/PrivateVotingLib.sol";

/// @title PrivateVoting
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Stateless Diamond facet for anonymous one-person-one-vote polling over Semaphore groups: a
///         member casts an anonymous ballot with a Semaphore proof (scope = poll id, message = choice),
///         and the scope-bound nullifier gives each member exactly one vote per poll.
/// @dev All logic lives in {PrivateVotingLib}. Composes the {ISemaphore} module (must be present in the
///      same diamond). 1-person-1-vote, not token-weighted.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original (composes Semaphore v4)
contract PrivateVoting is IPrivateVoting {
    /// @inheritdoc IPrivateVoting
    function createPoll(uint256 groupId, uint32 numChoices, uint64 startTime, uint64 endTime)
        external
        virtual
        returns (uint256)
    {
        return PrivateVotingLib.createPoll(groupId, numChoices, startTime, endTime);
    }

    /// @inheritdoc IPrivateVoting
    function vote(uint256 pollId, ISemaphore.SemaphoreProof calldata proof) external virtual {
        PrivateVotingLib.vote(pollId, proof);
    }

    /// @inheritdoc IPrivateVoting
    function pollCount() external view virtual returns (uint256) {
        return PrivateVotingLib.pollCount();
    }

    /// @inheritdoc IPrivateVoting
    function getPoll(uint256 pollId) external view virtual returns (PollView memory) {
        return PrivateVotingLib.getPoll(pollId);
    }

    /// @inheritdoc IPrivateVoting
    function getVotes(uint256 pollId, uint256 choice) external view virtual returns (uint256) {
        return PrivateVotingLib.getVotes(pollId, choice);
    }

    /// @inheritdoc IPrivateVoting
    function hasVoted(uint256 pollId, uint256 nullifier) external view virtual returns (bool) {
        return PrivateVotingLib.hasVoted(pollId, nullifier);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect PrivateVoting methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `createPoll(uint256,uint32,uint64,uint64)` 0x5fc5999b
    ///      `getPoll(uint256)` 0x1a8cbcaa
    ///      `getVotes(uint256,uint256)` 0x91f36633
    ///      `hasVoted(uint256,uint256)` 0x64390ff1
    ///      `pollCount()` 0x9207891d
    ///      `vote(uint256,(uint256,uint256,uint256,uint256,uint256,uint256[8]))` 0xd5d4738f
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"5fc5999b1a8cbcaa91f3663364390ff19207891dd5d4738f";
    }
}
