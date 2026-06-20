// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {NullifierRegistryLib} from "@lattice/privacy/libraries/NullifierRegistryLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Harness embedding a Registry in storage and exposing the library surface.
contract NullifierHarness {
    using NullifierRegistryLib for NullifierRegistryLib.Registry;

    NullifierRegistryLib.Registry internal reg;

    function spend(uint256 n) external {
        reg.spend(n);
    }

    function isSpent(uint256 n) external view returns (bool) {
        return reg.isSpent(n);
    }
}

/// @title NullifierRegistryLibTester
/// @notice Unit tests for the nullifier spent-set (double-spend protection).
contract NullifierRegistryLibTester is Test {
    NullifierHarness h;

    uint256 constant FIELD = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    // Canonical field elements (reduced so they are always < FIELD and non-zero).
    uint256 constant N1 = uint256(keccak256("nullifier-1")) % FIELD;
    uint256 constant N2 = uint256(keccak256("nullifier-2")) % FIELD;

    function setUp() public {
        h = new NullifierHarness();
    }

    function test_UnseenNullifierNotSpent() public view {
        assertFalse(h.isSpent(N1));
    }

    function test_SpendMarksSpent() public {
        h.spend(N1);
        assertTrue(h.isSpent(N1));
        assertFalse(h.isSpent(N2));
    }

    function test_DoubleSpendReverts() public {
        h.spend(N1);
        vm.expectRevert(abi.encodeWithSelector(NullifierRegistryLib.NullifierAlreadySpent.selector, N1));
        h.spend(N1);
    }

    function test_SpendZeroReverts() public {
        vm.expectRevert(NullifierRegistryLib.NullifierIsZero.selector);
        h.spend(0);
    }

    function test_SpendOutOfFieldReverts() public {
        // The field modulus itself and anything above it are non-canonical and rejected,
        // closing the n / n+p non-canonical double-spend at the library boundary.
        vm.expectRevert(abi.encodeWithSelector(NullifierRegistryLib.NullifierOutOfField.selector, FIELD));
        h.spend(FIELD);
        vm.expectRevert(abi.encodeWithSelector(NullifierRegistryLib.NullifierOutOfField.selector, type(uint256).max));
        h.spend(type(uint256).max);
    }

    function test_DistinctNullifiersIndependent() public {
        h.spend(N1);
        h.spend(N2);
        assertTrue(h.isSpent(N1));
        assertTrue(h.isSpent(N2));
    }
}
