// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";
import {Test} from "forge-std/Test.sol";

contract EnumerableSetHarness {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    EnumerableSet.Bytes32Set internal _bytes32Set;
    EnumerableSet.AddressSet internal _addressSet;
    EnumerableSet.UintSet internal _uintSet;

    function addBytes32(bytes32 v) external returns (bool) {
        return _bytes32Set.add(v);
    }

    function removeBytes32(bytes32 v) external returns (bool) {
        return _bytes32Set.remove(v);
    }

    function containsBytes32(bytes32 v) external view returns (bool) {
        return _bytes32Set.contains(v);
    }

    function lengthBytes32() external view returns (uint256) {
        return _bytes32Set.length();
    }

    function atBytes32(uint256 i) external view returns (bytes32) {
        return _bytes32Set.at(i);
    }

    function valuesBytes32() external view returns (bytes32[] memory) {
        return _bytes32Set.values();
    }

    function addAddress(address v) external returns (bool) {
        return _addressSet.add(v);
    }

    function removeAddress(address v) external returns (bool) {
        return _addressSet.remove(v);
    }

    function containsAddress(address v) external view returns (bool) {
        return _addressSet.contains(v);
    }

    function lengthAddress() external view returns (uint256) {
        return _addressSet.length();
    }

    function atAddress(uint256 i) external view returns (address) {
        return _addressSet.at(i);
    }

    function valuesAddress() external view returns (address[] memory) {
        return _addressSet.values();
    }

    function addUint(uint256 v) external returns (bool) {
        return _uintSet.add(v);
    }

    function removeUint(uint256 v) external returns (bool) {
        return _uintSet.remove(v);
    }

    function containsUint(uint256 v) external view returns (bool) {
        return _uintSet.contains(v);
    }

    function lengthUint() external view returns (uint256) {
        return _uintSet.length();
    }

    function atUint(uint256 i) external view returns (uint256) {
        return _uintSet.at(i);
    }

    function valuesUint() external view returns (uint256[] memory) {
        return _uintSet.values();
    }
}

contract EnumerableSetTest is Test {
    EnumerableSetHarness internal h;

    function setUp() public {
        h = new EnumerableSetHarness();
    }

    function test_AddFirstElementReturnsTrueAndSetsLength() public {
        bool added = h.addBytes32(bytes32(uint256(0x42)));
        assertTrue(added);
        assertEq(h.lengthBytes32(), 1);
        assertTrue(h.containsBytes32(bytes32(uint256(0x42))));
    }

    function test_AddDuplicateReturnsFalseAndLeavesLength() public {
        h.addBytes32(bytes32(uint256(0x42)));
        bool added = h.addBytes32(bytes32(uint256(0x42)));
        assertFalse(added);
        assertEq(h.lengthBytes32(), 1);
    }

    function test_ContainsAbsentReturnsFalse() public {
        assertFalse(h.containsBytes32(bytes32(uint256(0x99))));
    }

    function test_EmptyLengthIsZero() public view {
        assertEq(h.lengthBytes32(), 0);
    }

    function test_AtReturnsValueAtIndex() public {
        h.addBytes32(bytes32(uint256(0x01)));
        h.addBytes32(bytes32(uint256(0x02)));
        h.addBytes32(bytes32(uint256(0x03)));
        assertEq(h.atBytes32(0), bytes32(uint256(0x01)));
        assertEq(h.atBytes32(1), bytes32(uint256(0x02)));
        assertEq(h.atBytes32(2), bytes32(uint256(0x03)));
    }

    function test_AtOutOfBoundsReverts() public {
        h.addBytes32(bytes32(uint256(0x01)));
        vm.expectRevert();
        h.atBytes32(1);
    }

    function test_AtOnEmptySetReverts() public {
        vm.expectRevert();
        h.atBytes32(0);
    }

    function test_RemoveExistingReturnsTrueAndShrinks() public {
        h.addBytes32(bytes32(uint256(0xA)));
        bool removed = h.removeBytes32(bytes32(uint256(0xA)));
        assertTrue(removed);
        assertEq(h.lengthBytes32(), 0);
        assertFalse(h.containsBytes32(bytes32(uint256(0xA))));
    }

    function test_RemoveAbsentReturnsFalse() public {
        bool removed = h.removeBytes32(bytes32(uint256(0xB)));
        assertFalse(removed);
        assertEq(h.lengthBytes32(), 0);
    }

    function test_RemoveMiddleElementSwapsAndPops() public {
        bytes32 a = bytes32(uint256(0xA));
        bytes32 b = bytes32(uint256(0xB));
        bytes32 c = bytes32(uint256(0xC));
        h.addBytes32(a);
        h.addBytes32(b);
        h.addBytes32(c);

        h.removeBytes32(b);

        assertEq(h.lengthBytes32(), 2);
        assertTrue(h.containsBytes32(a));
        assertFalse(h.containsBytes32(b));
        assertTrue(h.containsBytes32(c));

        assertEq(h.atBytes32(0), a);
        assertEq(h.atBytes32(1), c);
    }

    function test_RemoveLastElementPopsWithoutSwap() public {
        bytes32 a = bytes32(uint256(0xA));
        bytes32 b = bytes32(uint256(0xB));
        h.addBytes32(a);
        h.addBytes32(b);

        h.removeBytes32(b);

        assertEq(h.lengthBytes32(), 1);
        assertEq(h.atBytes32(0), a);
    }

    function test_ReAddAfterRemoveWorks() public {
        bytes32 a = bytes32(uint256(0xA));
        h.addBytes32(a);
        h.removeBytes32(a);
        bool addedAgain = h.addBytes32(a);
        assertTrue(addedAgain);
        assertEq(h.lengthBytes32(), 1);
        assertTrue(h.containsBytes32(a));
    }

    function test_ValuesReturnsFullSnapshot() public {
        h.addBytes32(bytes32(uint256(0xA)));
        h.addBytes32(bytes32(uint256(0xB)));
        h.addBytes32(bytes32(uint256(0xC)));

        bytes32[] memory snap = h.valuesBytes32();
        assertEq(snap.length, 3);
        assertEq(snap[0], bytes32(uint256(0xA)));
        assertEq(snap[1], bytes32(uint256(0xB)));
        assertEq(snap[2], bytes32(uint256(0xC)));
    }

    function test_ValuesOnEmptySetReturnsEmpty() public view {
        bytes32[] memory snap = h.valuesBytes32();
        assertEq(snap.length, 0);
    }
}
