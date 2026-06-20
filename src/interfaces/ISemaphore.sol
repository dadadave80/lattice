// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ISemaphore
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice External interface for the Semaphore anonymous-membership / signaling module. Members join a
///         group (a Poseidon incremental Merkle tree of identity commitments) and later prove membership
///         in zero knowledge while broadcasting a message under a scope — without revealing which member
///         they are. A per-(group) nullifier prevents the same identity from signaling twice in a scope.
/// @dev Wraps the audited Semaphore v4 Groth16 verifier (called via {setVerifier}). Group membership uses
///      the shared incremental Merkle tree (Poseidon LeanIMT) with a recent-root history, so a proof
///      built against a slightly stale root still validates.
interface ISemaphore {
    /// @notice A Semaphore proof.
    /// @param merkleTreeDepth The depth of the tree the proof was generated against (1..32).
    /// @param merkleTreeRoot The group Merkle root the proof was generated against.
    /// @param nullifier The scope nullifier (prevents double-signaling within a scope).
    /// @param message The signaled message.
    /// @param scope The scope the proof is bound to.
    /// @param points The Groth16 proof points (`pA`, `pB`, `pC` flattened to 8 words).
    struct SemaphoreProof {
        uint256 merkleTreeDepth;
        uint256 merkleTreeRoot;
        uint256 nullifier;
        uint256 message;
        uint256 scope;
        uint256[8] points;
    }

    /// @dev Emitted when a group is created.
    event GroupCreated(uint256 indexed groupId, address indexed admin);

    /// @dev Emitted when a member is added to a group.
    event MemberAdded(uint256 indexed groupId, uint256 index, uint256 identityCommitment, uint256 merkleTreeRoot);

    /// @dev Emitted when a proof is validated against a group.
    event ProofValidated(
        uint256 indexed groupId,
        uint256 merkleTreeDepth,
        uint256 indexed merkleTreeRoot,
        uint256 nullifier,
        uint256 message,
        uint256 indexed scope,
        uint256[8] points
    );

    /// @dev Emitted when the Semaphore verifier address is set.
    event VerifierUpdated(address verifier);

    /// @dev Thrown when operating on a group that does not exist.
    error SemaphoreGroupDoesNotExist();
    /// @dev Thrown when the caller is not the group admin.
    error SemaphoreCallerIsNotGroupAdmin();
    /// @dev Thrown when validating a proof against a group with no members.
    error SemaphoreGroupHasNoMembers();
    /// @dev Thrown when the proof's Merkle tree depth is outside the supported range (1..32).
    error SemaphoreMerkleTreeDepthUnsupported();
    /// @dev Thrown when the proof's Merkle root is not a current or recent root of the group.
    error SemaphoreMerkleTreeRootNotInGroup();
    /// @dev Thrown when the proof's nullifier was already used in the group.
    error SemaphoreNullifierAlreadyUsed();
    /// @dev Thrown when proof verification fails.
    error SemaphoreInvalidProof();
    /// @dev Thrown when the verifier address has not been set.
    error SemaphoreVerifierNotSet();

    /// @dev Thrown when setting the verifier to the zero address.
    error SemaphoreVerifierIsZero();

    /// @notice Creates a new group administered by the caller.
    /// @return groupId The new group id.
    function createGroup() external returns (uint256 groupId);

    /// @notice Creates a new group administered by `admin`.
    /// @param admin The group admin (may add members).
    /// @return groupId The new group id.
    function createGroup(address admin) external returns (uint256 groupId);

    /// @notice Adds a member (identity commitment) to a group. Only the group admin.
    /// @param groupId The group id.
    /// @param identityCommitment The member's identity commitment.
    function addMember(uint256 groupId, uint256 identityCommitment) external;

    /// @notice Adds many members to a group. Only the group admin.
    /// @param groupId The group id.
    /// @param identityCommitments The members' identity commitments, in order.
    function addMembers(uint256 groupId, uint256[] calldata identityCommitments) external;

    /// @notice Validates a proof against a group and consumes its nullifier (state-changing).
    /// @dev Reverts if the group/depth/root/nullifier checks fail or the proof is invalid.
    /// @param groupId The group id.
    /// @param proof The Semaphore proof.
    function validateProof(uint256 groupId, SemaphoreProof calldata proof) external;

    /// @notice Verifies a proof against a group WITHOUT consuming the nullifier.
    /// @param groupId The group id.
    /// @param proof The Semaphore proof.
    /// @return True iff the proof is valid for the group.
    function verifyProof(uint256 groupId, SemaphoreProof calldata proof) external view returns (bool);

    /// @notice Sets the Semaphore verifier contract. Gated on the default admin role.
    /// @param verifier The {ISemaphoreVerifier} address.
    function setVerifier(address verifier) external;

    /// @notice Returns the number of groups created.
    function groupCount() external view returns (uint256);

    /// @notice Returns the admin of `groupId`.
    function groupAdmin(uint256 groupId) external view returns (address);

    /// @notice Returns the current Merkle root of `groupId`.
    function getMerkleTreeRoot(uint256 groupId) external view returns (uint256);

    /// @notice Returns the number of members in `groupId`.
    function getMerkleTreeSize(uint256 groupId) external view returns (uint256);

    /// @notice Returns whether `identityCommitment` is a member of `groupId`.
    function hasMember(uint256 groupId, uint256 identityCommitment) external view returns (bool);

    /// @notice Returns the configured Semaphore verifier address.
    function verifier() external view returns (address);
}
