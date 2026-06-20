// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IncrementalMerkleTreeLib} from "@lattice/privacy/libraries/IncrementalMerkleTreeLib.sol";
import {
    LeafAlreadyExists,
    LeafCannotBeZero,
    LeafGreaterThanSnarkScalarField
} from "@zk-kit/lean-imt.sol/InternalLeanIMT.sol";
import {Test} from "forge-std/Test.sol";
import {PoseidonT3} from "poseidon-solidity/PoseidonT3.sol";

/// @notice Harness embedding a Tree in storage and exposing the library surface.
contract MerkleHarness {
    using IncrementalMerkleTreeLib for IncrementalMerkleTreeLib.Tree;

    IncrementalMerkleTreeLib.Tree internal tree;

    function insert(uint256 leaf) external returns (uint256) {
        return tree.insert(leaf);
    }

    function root() external view returns (uint256) {
        return tree.root();
    }

    function isKnownRoot(uint256 r) external view returns (bool) {
        return tree.isKnownRoot(r);
    }

    function has(uint256 leaf) external view returns (bool) {
        return tree.has(leaf);
    }

    function size() external view returns (uint256) {
        return tree.size();
    }

    function depth() external view returns (uint256) {
        return tree.depth();
    }
}

/// @title IncrementalMerkleTreeLibTester
/// @notice Unit tests for the Poseidon incremental Merkle tree + root-history ring.
contract IncrementalMerkleTreeLibTester is Test {
    MerkleHarness h;

    uint256 constant FIELD = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

    function setUp() public {
        h = new MerkleHarness();
    }

    function test_EmptyTree() public view {
        assertEq(h.root(), 0);
        assertEq(h.size(), 0);
        assertFalse(h.isKnownRoot(0));
        assertFalse(h.isKnownRoot(uint256(keccak256("anything"))));
    }

    function test_SingleLeafRootIsLeaf() public {
        // LeanIMT: a one-leaf tree's root is the leaf itself.
        uint256 r = h.insert(1);
        assertEq(r, 1);
        assertEq(h.root(), 1);
        assertEq(h.size(), 1);
    }

    function test_TwoLeavesRootIsPoseidon() public {
        // The audited PoseidonT3 is the oracle: a two-leaf root must equal Poseidon(l0, l1).
        h.insert(7);
        uint256 r = h.insert(9);
        assertEq(r, PoseidonT3.hash([uint256(7), uint256(9)]));
        assertEq(h.root(), PoseidonT3.hash([uint256(7), uint256(9)]));
    }

    function test_HasLeaf() public {
        h.insert(5);
        assertTrue(h.has(5));
        assertFalse(h.has(6));
    }

    function test_KnownRootsTrackHistory() public {
        uint256 r1 = h.insert(1);
        assertTrue(h.isKnownRoot(r1));
        uint256 r2 = h.insert(2);
        // both the current and the previous root remain valid for proofs
        assertTrue(h.isKnownRoot(r2));
        assertTrue(h.isKnownRoot(r1));
        // an unseen root and the zero root are never known
        assertFalse(h.isKnownRoot(uint256(keccak256("never"))));
        assertFalse(h.isKnownRoot(0));
    }

    function test_RootHistoryRingEvictsOldest() public {
        uint256 root1;
        uint256 root2;
        uint256 current;
        // Insert ROOT_HISTORY_SIZE + 1 (= 31) distinct non-zero leaves.
        for (uint256 leaf = 1; leaf <= 31; ++leaf) {
            current = h.insert(leaf);
            if (leaf == 1) root1 = current;
            if (leaf == 2) root2 = current;
        }
        // The ring holds the last 30 roots (inserts 2..31); the very first root is evicted.
        assertFalse(h.isKnownRoot(root1));
        assertTrue(h.isKnownRoot(root2));
        assertTrue(h.isKnownRoot(current));
        assertEq(h.size(), 31);
    }

    function test_RejectZeroLeaf() public {
        vm.expectRevert(LeafCannotBeZero.selector);
        h.insert(0);
    }

    function test_RejectDuplicateLeaf() public {
        h.insert(3);
        vm.expectRevert(LeafAlreadyExists.selector);
        h.insert(3);
    }

    function test_RejectLeafGteField() public {
        vm.expectRevert(LeafGreaterThanSnarkScalarField.selector);
        h.insert(FIELD);
    }
}
