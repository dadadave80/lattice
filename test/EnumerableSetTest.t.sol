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
}
