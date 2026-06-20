// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InternalLeanIMT, LeanIMTData} from "@zk-kit/lean-imt.sol/InternalLeanIMT.sol";

/// @title IncrementalMerkleTreeLib
/// @author David Dada
/// @notice Poseidon-hashed, dynamic-depth incremental Merkle tree with a recent-root
///         history ring. The commitment accumulator for nullifier-based privacy schemes:
///         insert commitments as leaves, then prove membership in a ZK circuit against
///         any recent root.
/// @dev Wraps the PSE-audited LeanIMT (Semaphore v4 audit, Mar 2024) for the tree math
///      and adds a Tornado-style root-history ring so a proof built against a slightly
///      stale root still verifies as the tree grows between proof generation and
///      submission. Poseidon hashing is MANDATORY: the proving circuits hash with
///      Poseidon, so a keccak tree (e.g. OpenZeppelin MerkleProof) would NOT verify and
///      must never be substituted. Stateless helper — no own ERC-7201 slot; `Tree` is
///      held inline in the consumer's namespaced storage. Leaves must be non-zero and
///      strictly less than the SNARK scalar field (enforced by LeanIMT).
library IncrementalMerkleTreeLib {
    using InternalLeanIMT for LeanIMTData;

    /// @dev Number of recent roots retained for membership proofs. A proof remains valid
    ///      as long as fewer than this many insertions happen between generation and use.
    uint256 internal constant ROOT_HISTORY_SIZE = 30;

    struct Tree {
        LeanIMTData _leanIMT; // audited LeanIMT tree state (size, depth, sideNodes, leaves)
        uint256 _currentRootIndex; // ring position of the most recent root
        uint256 _rootCount; // total number of roots ever recorded
        mapping(uint256 index => uint256 root) _rootHistory; // ring buffer of recent roots
    }

    /// @notice Inserts `leaf` and records the new root in the history ring.
    /// @param self The tree storage reference.
    /// @param leaf The leaf (commitment) to insert; must be non-zero and < SNARK field.
    /// @return newRoot The tree root after insertion.
    function insert(Tree storage self, uint256 leaf) internal returns (uint256 newRoot) {
        newRoot = self._leanIMT._insert(leaf);
        uint256 nextIndex = self._rootCount == 0 ? 0 : (self._currentRootIndex + 1) % ROOT_HISTORY_SIZE;
        self._currentRootIndex = nextIndex;
        self._rootHistory[nextIndex] = newRoot;
        unchecked {
            ++self._rootCount;
        }
    }

    /// @notice Returns the current tree root (0 for an empty tree).
    /// @param self The tree storage reference.
    function root(Tree storage self) internal view returns (uint256) {
        return self._leanIMT._root();
    }

    /// @notice Returns whether `r` is the current root or one of the recent historical roots.
    /// @dev The zero root is never "known". Walks the live ring window newest-first.
    /// @param self The tree storage reference.
    /// @param r The candidate root.
    function isKnownRoot(Tree storage self, uint256 r) internal view returns (bool) {
        if (r == 0) return false;
        uint256 count = self._rootCount;
        if (count == 0) return false;
        uint256 window = count < ROOT_HISTORY_SIZE ? count : ROOT_HISTORY_SIZE;
        uint256 i = self._currentRootIndex;
        for (uint256 n = 0; n < window;) {
            if (self._rootHistory[i] == r) return true;
            if (i == 0) i = ROOT_HISTORY_SIZE;
            unchecked {
                --i;
                ++n;
            }
        }
        return false;
    }

    /// @notice Returns whether `leaf` is present in the tree.
    /// @param self The tree storage reference.
    /// @param leaf The leaf to query.
    function has(Tree storage self, uint256 leaf) internal view returns (bool) {
        return self._leanIMT._has(leaf);
    }

    /// @notice Returns the number of leaves in the tree.
    /// @param self The tree storage reference.
    function size(Tree storage self) internal view returns (uint256) {
        return self._leanIMT.size;
    }

    /// @notice Returns the current dynamic depth of the tree.
    /// @param self The tree storage reference.
    function depth(Tree storage self) internal view returns (uint256) {
        return self._leanIMT.depth;
    }
}
