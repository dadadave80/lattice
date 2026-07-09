// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ISemaphore} from "@lattice/interfaces/privacy/ISemaphore.sol";
import {IncrementalMerkleTreeLib} from "@lattice/privacy/libraries/IncrementalMerkleTreeLib.sol";
import {NullifierRegistryLib} from "@lattice/privacy/libraries/NullifierRegistryLib.sol";
import {ISemaphoreVerifier} from "@semaphore/ISemaphoreVerifier.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.Semaphore")) - 1)) & ~bytes32(uint256(0xff))`.
///      Verify with: `cast index-erc7201 "lattice.storage.Semaphore"`.
bytes32 constant SEMAPHORE_STORAGE_SLOT = 0x9014b6f2f89a94726c6607d3b9e5562f77c44e9f80791dbbfea2ef3de33d0300;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant SEMAPHORE_ERC165_STORAGE_LOCATION = 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0xf497879d is `type(ISemaphore).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xf497879d), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ISEMAPHORE_SLOT = 0xf2439559430b40518d710e6342516a19266235963e7106afd03350497fe51040;

/// @notice Per-group state: the membership tree, the scope-nullifier spent-set, the admin, and existence.
struct Group {
    IncrementalMerkleTreeLib.Tree tree;
    NullifierRegistryLib.Registry nullifiers;
    address admin;
    bool exists;
}

/// @notice ERC-7201 namespaced storage for the Semaphore module.
/// @dev APPEND-ONLY: new fields may only be added at the end to preserve the upgrade-safe layout.
/// @custom:storage-location erc7201:lattice.storage.Semaphore
struct SemaphoreStorage {
    /// @dev group id => group state.
    mapping(uint256 groupId => Group group) groups;
    /// @dev Number of groups created (also the next group id).
    uint256 groupCount;
    /// @dev The Semaphore (Groth16) verifier contract.
    address verifier;
}

/// @title SemaphoreLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Semaphore (https://github.com/semaphore-protocol/semaphore)
/// @notice Library implementing the Semaphore anonymous-membership / signaling module: groups of identity
///         commitments (Poseidon incremental Merkle trees) and zero-knowledge membership + signaling
///         proofs validated against the audited Semaphore v4 verifier, with per-group scope nullifiers.
/// @dev Three-layer pattern: this library holds the logic + namespaced storage; the stateless {Semaphore}
///      facet forwards to it. Membership uses {IncrementalMerkleTreeLib} (Poseidon LeanIMT + recent-root
///      history) and double-signaling protection uses {NullifierRegistryLib}. The Groth16 verification is
///      delegated to the configurable, audited {ISemaphoreVerifier}.
library SemaphoreLib {
    using IncrementalMerkleTreeLib for IncrementalMerkleTreeLib.Tree;
    using NullifierRegistryLib for NullifierRegistryLib.Registry;

    /// @dev Minimum / maximum supported Merkle tree depth (matches Semaphore v4).
    uint256 internal constant MIN_DEPTH = 1;
    uint256 internal constant MAX_DEPTH = 32;

    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function semaphoreStorage() internal pure returns (SemaphoreStorage storage $) {
        assembly {
            $.slot := SEMAPHORE_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the Semaphore module with a verifier.
    /// @dev Must be called inside a pre/postInitializer block. Registers ISemaphore for ERC-165.
    /// @param verifier_ The {ISemaphoreVerifier} contract address.
    function __Semaphore_init(address verifier_) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        if (verifier_ == address(0)) revert ISemaphore.SemaphoreVerifierIsZero();
        semaphoreStorage().verifier = verifier_;
        registerInterface();
    }

    /// @notice Registers support for the ISemaphore interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ISEMAPHORE_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              CONFIGURATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets the Semaphore verifier. Gated on the default admin role.
    function setVerifier(address verifier_) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (verifier_ == address(0)) revert ISemaphore.SemaphoreVerifierIsZero();
        semaphoreStorage().verifier = verifier_;
        emit ISemaphore.VerifierUpdated(verifier_);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            GROUP MANAGEMENT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Creates a group administered by `admin`.
    function createGroup(address admin) internal returns (uint256 groupId) {
        SemaphoreStorage storage $ = semaphoreStorage();
        groupId = $.groupCount++;
        Group storage g = $.groups[groupId];
        g.admin = admin;
        g.exists = true;
        emit ISemaphore.GroupCreated(groupId, admin);
    }

    /// @notice Adds a member to a group. Only the group admin.
    function addMember(uint256 groupId, uint256 identityCommitment) internal {
        Group storage g = _adminGroup(groupId);
        uint256 root = g.tree.insert(identityCommitment);
        emit ISemaphore.MemberAdded(groupId, g.tree.size() - 1, identityCommitment, root);
    }

    /// @notice Adds many members to a group, in order. Only the group admin.
    function addMembers(uint256 groupId, uint256[] calldata identityCommitments) internal {
        Group storage g = _adminGroup(groupId);
        for (uint256 i; i < identityCommitments.length; ++i) {
            uint256 root = g.tree.insert(identityCommitments[i]);
            emit ISemaphore.MemberAdded(groupId, g.tree.size() - 1, identityCommitments[i], root);
        }
    }

    /// @dev Loads a group, reverting if it does not exist or the caller is not its admin.
    function _adminGroup(uint256 groupId) private view returns (Group storage g) {
        g = semaphoreStorage().groups[groupId];
        if (!g.exists) revert ISemaphore.SemaphoreGroupDoesNotExist();
        if (msg.sender != g.admin) revert ISemaphore.SemaphoreCallerIsNotGroupAdmin();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              VERIFICATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Validates a proof against a group and consumes its nullifier.
    function validateProof(uint256 groupId, ISemaphore.SemaphoreProof calldata proof) internal {
        Group storage g = semaphoreStorage().groups[groupId];
        if (!g.exists) revert ISemaphore.SemaphoreGroupDoesNotExist();
        // Reject a reused nullifier before doing any work (anti double-signaling).
        if (g.nullifiers.isSpent(proof.nullifier)) revert ISemaphore.SemaphoreNullifierAlreadyUsed();
        if (!_verify(g, proof)) revert ISemaphore.SemaphoreInvalidProof();
        // CEI: consume the nullifier before emitting.
        g.nullifiers.spend(proof.nullifier);
        emit ISemaphore.ProofValidated(
            groupId,
            proof.merkleTreeDepth,
            proof.merkleTreeRoot,
            proof.nullifier,
            proof.message,
            proof.scope,
            proof.points
        );
    }

    /// @notice Verifies a proof against a group without consuming its nullifier.
    function verifyProof(uint256 groupId, ISemaphore.SemaphoreProof calldata proof) internal view returns (bool) {
        Group storage g = semaphoreStorage().groups[groupId];
        if (!g.exists) revert ISemaphore.SemaphoreGroupDoesNotExist();
        return _verify(g, proof);
    }

    /// @dev Shared depth/root checks + delegation to the audited Semaphore verifier.
    function _verify(Group storage g, ISemaphore.SemaphoreProof calldata proof) private view returns (bool) {
        address v = semaphoreStorage().verifier;
        if (v == address(0)) revert ISemaphore.SemaphoreVerifierNotSet();
        if (proof.merkleTreeDepth < MIN_DEPTH || proof.merkleTreeDepth > MAX_DEPTH) {
            revert ISemaphore.SemaphoreMerkleTreeDepthUnsupported();
        }
        if (g.tree.size() == 0) revert ISemaphore.SemaphoreGroupHasNoMembers();
        if (!g.tree.isKnownRoot(proof.merkleTreeRoot)) revert ISemaphore.SemaphoreMerkleTreeRootNotInGroup();
        return ISemaphoreVerifier(v)
            .verifyProof(
                [proof.points[0], proof.points[1]],
                [[proof.points[2], proof.points[3]], [proof.points[4], proof.points[5]]],
                [proof.points[6], proof.points[7]],
                [proof.merkleTreeRoot, proof.nullifier, _hash(proof.message), _hash(proof.scope)],
                proof.merkleTreeDepth
            );
    }

    /// @dev keccak256 hash of a value compatible with the SNARK scalar field (matches Semaphore v4).
    function _hash(uint256 value) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(value))) >> 8;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 GETTERS
    //////////////////////////////////////////////////////////////////////////*//

    function groupCount() internal view returns (uint256) {
        return semaphoreStorage().groupCount;
    }

    function groupAdmin(uint256 groupId) internal view returns (address) {
        return semaphoreStorage().groups[groupId].admin;
    }

    function getMerkleTreeRoot(uint256 groupId) internal view returns (uint256) {
        return semaphoreStorage().groups[groupId].tree.root();
    }

    function getMerkleTreeSize(uint256 groupId) internal view returns (uint256) {
        return semaphoreStorage().groups[groupId].tree.size();
    }

    function hasMember(uint256 groupId, uint256 identityCommitment) internal view returns (bool) {
        return semaphoreStorage().groups[groupId].tree.has(identityCommitment);
    }

    function verifier() internal view returns (address) {
        return semaphoreStorage().verifier;
    }
}
