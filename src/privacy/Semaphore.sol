// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ISemaphore} from "@lattice/interfaces/ISemaphore.sol";
import {SemaphoreLib} from "@lattice/privacy/libraries/SemaphoreLib.sol";

/// @title Semaphore
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Stateless Diamond facet for Semaphore anonymous membership / signaling: create groups, add
///         identity commitments, and validate zero-knowledge membership + signaling proofs.
/// @dev All logic lives in {SemaphoreLib}. Membership uses the Poseidon incremental Merkle tree; proof
///      verification is delegated to the audited Semaphore v4 verifier (set via {setVerifier}); a
///      per-group scope nullifier prevents double-signaling.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Wraps the audited Semaphore v4 (PSE) Groth16 verifier; group / nullifier / root
///         logic over Lattice's own Poseidon Merkle + nullifier libraries.
contract Semaphore is ISemaphore {
    /// @inheritdoc ISemaphore
    function createGroup() external virtual returns (uint256) {
        return SemaphoreLib.createGroup(msg.sender);
    }

    /// @inheritdoc ISemaphore
    function createGroup(address admin) external virtual returns (uint256) {
        return SemaphoreLib.createGroup(admin);
    }

    /// @inheritdoc ISemaphore
    function addMember(uint256 groupId, uint256 identityCommitment) external virtual {
        SemaphoreLib.addMember(groupId, identityCommitment);
    }

    /// @inheritdoc ISemaphore
    function addMembers(uint256 groupId, uint256[] calldata identityCommitments) external virtual {
        SemaphoreLib.addMembers(groupId, identityCommitments);
    }

    /// @inheritdoc ISemaphore
    function validateProof(uint256 groupId, SemaphoreProof calldata proof) external virtual {
        SemaphoreLib.validateProof(groupId, proof);
    }

    /// @inheritdoc ISemaphore
    function verifyProof(uint256 groupId, SemaphoreProof calldata proof) external view virtual returns (bool) {
        return SemaphoreLib.verifyProof(groupId, proof);
    }

    /// @inheritdoc ISemaphore
    function setVerifier(address verifier_) external virtual {
        SemaphoreLib.setVerifier(verifier_);
    }

    /// @inheritdoc ISemaphore
    function groupCount() external view virtual returns (uint256) {
        return SemaphoreLib.groupCount();
    }

    /// @inheritdoc ISemaphore
    function groupAdmin(uint256 groupId) external view virtual returns (address) {
        return SemaphoreLib.groupAdmin(groupId);
    }

    /// @inheritdoc ISemaphore
    function getMerkleTreeRoot(uint256 groupId) external view virtual returns (uint256) {
        return SemaphoreLib.getMerkleTreeRoot(groupId);
    }

    /// @inheritdoc ISemaphore
    function getMerkleTreeSize(uint256 groupId) external view virtual returns (uint256) {
        return SemaphoreLib.getMerkleTreeSize(groupId);
    }

    /// @inheritdoc ISemaphore
    function hasMember(uint256 groupId, uint256 identityCommitment) external view virtual returns (bool) {
        return SemaphoreLib.hasMember(groupId, identityCommitment);
    }

    /// @inheritdoc ISemaphore
    function verifier() external view virtual returns (address) {
        return SemaphoreLib.verifier();
    }
}
