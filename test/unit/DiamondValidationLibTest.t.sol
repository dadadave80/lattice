// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondValidationLib} from "@lattice/governance/libraries/DiamondValidationLib.sol";
import {Test} from "forge-std/Test.sol";

/// @title DiamondValidationLibTest
/// @notice Unit tests for the pure ERC-7201 namespace-disjointness validation.
contract DiamondValidationLibTest is Test {
    /// @dev Thin wrapper so vm.expectRevert can target the internal library call via an external frame.
    function callAssert(string[] memory ids) external pure {
        DiamondValidationLib.assertNamespacesDisjoint(ids);
    }

    function test_DisjointNamespacesPass() public view {
        string[] memory ids = new string[](3);
        ids[0] = "lattice.storage.AccessControl";
        ids[1] = "lattice.storage.Governor";
        ids[2] = "lattice.storage.GovernedDiamondCut";
        // Must not revert.
        this.callAssert(ids);
    }

    function test_EmptyArrayPasses() public view {
        string[] memory ids = new string[](0);
        this.callAssert(ids);
    }

    function test_SingleElementPasses() public view {
        string[] memory ids = new string[](1);
        ids[0] = "lattice.storage.Governor";
        this.callAssert(ids);
    }

    function test_DuplicateNamespaceReverts() public {
        string[] memory ids = new string[](3);
        ids[0] = "lattice.storage.Governor";
        ids[1] = "lattice.storage.AccessControl";
        ids[2] = "lattice.storage.Governor"; // duplicate of [0]
        bytes32 slot =
            keccak256(abi.encode(uint256(keccak256(bytes("lattice.storage.Governor"))) - 1)) & ~bytes32(uint256(0xff));
        vm.expectRevert(
            abi.encodeWithSelector(
                DiamondValidationLib.NamespaceCollision.selector,
                slot,
                "lattice.storage.Governor",
                "lattice.storage.Governor"
            )
        );
        this.callAssert(ids);
    }

    /// @notice Two DIFFERENT namespaces that hash to the same slot would also revert. We can't easily
    ///         find such a pair, so we assert the slot helper is the canonical derivation instead.
    function test_SlotHelperMatchesCanonicalDerivation() public pure {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256(bytes("lattice.storage.Governor"))) - 1)) & ~bytes32(uint256(0xff));
        assertEq(DiamondValidationLib.erc7201Slot("lattice.storage.Governor"), expected);
    }
}
