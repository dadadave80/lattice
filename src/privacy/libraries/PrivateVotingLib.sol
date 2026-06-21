// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IPrivateVoting} from "@lattice/interfaces/IPrivateVoting.sol";
import {ISemaphore} from "@lattice/interfaces/ISemaphore.sol";
import {NullifierRegistryLib} from "@lattice/privacy/libraries/NullifierRegistryLib.sol";
import {SemaphoreLib} from "@lattice/privacy/libraries/SemaphoreLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.PrivateVoting")) - 1)) & ~bytes32(uint256(0xff))`.
///      Verify with: `cast index-erc7201 "lattice.storage.PrivateVoting"`.
bytes32 constant PRIVATE_VOTING_STORAGE_SLOT = 0x366a7e9d1ddfe6eaa85ec4e6a71a0be592797e3e9ab0151a827465f6ed6bb900;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant PRIVATE_VOTING_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0xf750b661 is `type(IPrivateVoting).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xf750b661), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IPRIVATEVOTING_SLOT = 0xd7a71e51b42fc01807cbfbb5db7d2ead6dbf4db6187d1c815fc074c4ac95ba7c;

/// @notice A poll's storage.
/// @dev APPEND-ONLY: new fields may only be added at the end.
struct Poll {
    uint256 groupId; // the Semaphore group whose members may vote
    NullifierRegistryLib.Registry nullifiers; // per-poll spent set (scope = pollId)
    mapping(uint256 choice => uint256 votes) tally; // votes per option
    uint256 totalVotes; // total ballots counted
    address creator; // the group admin who created the poll
    uint32 numChoices; // valid options: 0..numChoices-1
    uint64 startTime; // voting opens (0 = immediately)
    uint64 endTime; // voting closes (0 = never)
    bool exists;
}

/// @notice ERC-7201 namespaced storage for the PrivateVoting module.
/// @dev APPEND-ONLY: new fields may only be added at the end to preserve the upgrade-safe layout.
/// @custom:storage-location erc7201:lattice.storage.PrivateVoting
struct PrivateVotingStorage {
    /// @dev poll id (1-based) => poll.
    mapping(uint256 pollId => Poll poll) _polls;
    /// @dev number of polls created.
    uint256 _pollCount;
}

/// @title PrivateVotingLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library implementing anonymous one-person-one-vote polling over Semaphore groups. Each member
///         votes once per poll via a Semaphore proof (scope = poll id, message = choice); the scope-bound
///         nullifier enforces one ballot while the vote stays anonymous.
/// @dev Three-layer pattern: this library holds the logic + namespaced storage; the stateless
///      {PrivateVoting} facet forwards to it. Composes {SemaphoreLib} for the membership + ZK check
///      (the {ISemaphore} module must be present in the same diamond and the group created there).
library PrivateVotingLib {
    using NullifierRegistryLib for NullifierRegistryLib.Registry;

    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function privateVotingStorage() internal pure returns (PrivateVotingStorage storage $) {
        assembly {
            $.slot := PRIVATE_VOTING_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the PrivateVoting module.
    /// @dev Must be called inside a pre/postInitializer block. Registers IPrivateVoting for ERC-165.
    function __PrivateVoting_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    /// @notice Registers support for the IPrivateVoting interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IPRIVATEVOTING_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  POLLS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Creates a poll over `groupId`. Only the Semaphore group admin may create it.
    function createPoll(uint256 groupId, uint32 numChoices, uint64 startTime, uint64 endTime)
        internal
        returns (uint256 pollId)
    {
        if (SemaphoreLib.groupAdmin(groupId) != msg.sender) revert IPrivateVoting.PrivateVotingNotGroupAdmin();
        if (numChoices < 2) revert IPrivateVoting.PrivateVotingInvalidNumChoices();
        if (endTime != 0 && endTime <= startTime) revert IPrivateVoting.PrivateVotingInvalidTimeWindow();

        PrivateVotingStorage storage $ = privateVotingStorage();
        pollId = ++$._pollCount; // 1-based; voters use this as the Semaphore scope
        Poll storage p = $._polls[pollId];
        p.groupId = groupId;
        p.numChoices = numChoices;
        p.startTime = startTime;
        p.endTime = endTime;
        p.creator = msg.sender;
        p.exists = true;

        emit IPrivateVoting.PollCreated(pollId, groupId, msg.sender, numChoices, startTime, endTime);
    }

    /// @notice Casts an anonymous ballot. `proof.scope` must equal `pollId`; `proof.message` is the choice.
    /// @dev CEI: the nullifier is spent before the {VoteCast} event (no external interaction either way).
    function vote(uint256 pollId, ISemaphore.SemaphoreProof calldata proof) internal {
        Poll storage p = privateVotingStorage()._polls[pollId];
        if (!p.exists) revert IPrivateVoting.PrivateVotingPollDoesNotExist();
        if (p.startTime != 0 && block.timestamp < p.startTime) revert IPrivateVoting.PrivateVotingNotOpen();
        if (p.endTime != 0 && block.timestamp > p.endTime) revert IPrivateVoting.PrivateVotingClosed();
        if (proof.scope != pollId) revert IPrivateVoting.PrivateVotingScopeMismatch();
        if (proof.message >= p.numChoices) revert IPrivateVoting.PrivateVotingInvalidChoice();

        // Membership + zero-knowledge check via the audited Semaphore verifier (binds message + scope).
        if (!SemaphoreLib.verifyProof(p.groupId, proof)) revert IPrivateVoting.PrivateVotingInvalidProof();

        // One ballot per (voter, poll): the scope-bound nullifier is spent in this poll's own set.
        if (p.nullifiers.isSpent(proof.nullifier)) revert IPrivateVoting.PrivateVotingAlreadyVoted();
        p.nullifiers.spend(proof.nullifier);

        unchecked {
            ++p.tally[proof.message];
            ++p.totalVotes;
        }
        emit IPrivateVoting.VoteCast(pollId, proof.message, proof.nullifier);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 GETTERS
    //////////////////////////////////////////////////////////////////////////*//

    function pollCount() internal view returns (uint256) {
        return privateVotingStorage()._pollCount;
    }

    function getPoll(uint256 pollId) internal view returns (IPrivateVoting.PollView memory view_) {
        Poll storage p = privateVotingStorage()._polls[pollId];
        if (!p.exists) revert IPrivateVoting.PrivateVotingPollDoesNotExist();
        view_ = IPrivateVoting.PollView({
            groupId: p.groupId,
            numChoices: p.numChoices,
            creator: p.creator,
            startTime: p.startTime,
            endTime: p.endTime,
            totalVotes: p.totalVotes
        });
    }

    function getVotes(uint256 pollId, uint256 choice) internal view returns (uint256) {
        return privateVotingStorage()._polls[pollId].tally[choice];
    }

    function hasVoted(uint256 pollId, uint256 nullifier) internal view returns (bool) {
        return privateVotingStorage()._polls[pollId].nullifiers.isSpent(nullifier);
    }
}
