// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {ISemaphore} from "@lattice/interfaces/ISemaphore.sol";

/// @title IPrivateVoting
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice External interface for anonymous one-person-one-vote polling. A poll is bound to a Semaphore
///         group (the electorate); a member casts a ballot with a Semaphore proof whose `scope` is the
///         poll id and whose `message` is the vote choice. The scope-bound nullifier gives each member
///         exactly one vote per poll while keeping the vote anonymous.
/// @dev Composes the {ISemaphore} module: voting reuses that group's membership + the audited verifier
///      for the zero-knowledge check, and keeps its OWN per-poll nullifier set for double-vote
///      protection (so voting nullifiers never collide with general Semaphore signalling). This is
///      1-person-1-vote, NOT token-weighted: private weighted voting needs a bespoke circuit and is out
///      of scope. The {ISemaphore} module must be present in the same diamond and its groups created
///      there; `proof.scope` MUST equal the poll id.
interface IPrivateVoting {
    /// @notice A poll's public configuration (the per-choice tally is read via {getVotes}).
    /// @param groupId The Semaphore group whose members may vote.
    /// @param numChoices Number of valid options; votes use `0 .. numChoices-1`.
    /// @param creator The group admin who created the poll.
    /// @param startTime Unix time voting opens (0 = open immediately).
    /// @param endTime Unix time voting closes (0 = never closes).
    /// @param totalVotes Total ballots cast.
    struct PollView {
        uint256 groupId;
        uint32 numChoices;
        address creator;
        uint64 startTime;
        uint64 endTime;
        uint256 totalVotes;
    }

    /// @dev Thrown when the poll id does not exist.
    error PrivateVotingPollDoesNotExist();
    /// @dev Thrown when the caller is not the admin of the poll's Semaphore group.
    error PrivateVotingNotGroupAdmin();
    /// @dev Thrown when creating a poll with fewer than two choices.
    error PrivateVotingInvalidNumChoices();
    /// @dev Thrown when `endTime` is set and is not after `startTime`.
    error PrivateVotingInvalidTimeWindow();
    /// @dev Thrown when voting before `startTime`.
    error PrivateVotingNotOpen();
    /// @dev Thrown when voting after `endTime`.
    error PrivateVotingClosed();
    /// @dev Thrown when `proof.scope` is not the poll id (the ballot is for a different poll).
    error PrivateVotingScopeMismatch();
    /// @dev Thrown when `proof.message` (the choice) is `>= numChoices`.
    error PrivateVotingInvalidChoice();
    /// @dev Thrown when the Semaphore membership proof does not verify.
    error PrivateVotingInvalidProof();
    /// @dev Thrown when the proof's nullifier has already voted in this poll.
    error PrivateVotingAlreadyVoted();

    /// @dev Emitted when a poll is created.
    event PollCreated(
        uint256 indexed pollId,
        uint256 indexed groupId,
        address indexed creator,
        uint32 numChoices,
        uint64 startTime,
        uint64 endTime
    );

    /// @dev Emitted when a ballot is counted. `nullifier` is the public, scope-bound tag (not linkable
    ///      to an identity); `choice` is the counted option.
    event VoteCast(uint256 indexed pollId, uint256 indexed choice, uint256 nullifier);

    /// @notice Creates a poll over `groupId`. Only the group admin may create polls for it.
    /// @param groupId The Semaphore group whose members may vote.
    /// @param numChoices Number of options (>= 2).
    /// @param startTime Unix time voting opens (0 = immediately).
    /// @param endTime Unix time voting closes (0 = never).
    /// @return pollId The new poll id (1-based); voters must use this as the Semaphore `scope`.
    function createPoll(uint256 groupId, uint32 numChoices, uint64 startTime, uint64 endTime)
        external
        returns (uint256 pollId);

    /// @notice Casts an anonymous ballot in `pollId`. `proof.scope` must equal `pollId` and
    ///         `proof.message` is the chosen option; the nullifier prevents a second ballot.
    /// @param pollId The poll to vote in.
    /// @param proof The Semaphore proof of membership binding the choice + poll.
    function vote(uint256 pollId, ISemaphore.SemaphoreProof calldata proof) external;

    /// @notice Returns the number of polls created.
    function pollCount() external view returns (uint256);

    /// @notice Returns the public configuration of `pollId`.
    function getPoll(uint256 pollId) external view returns (PollView memory);

    /// @notice Returns the vote count for `choice` in `pollId`.
    function getVotes(uint256 pollId, uint256 choice) external view returns (uint256);

    /// @notice Returns whether `nullifier` has already voted in `pollId`.
    function hasVoted(uint256 pollId, uint256 nullifier) external view returns (bool);
}
