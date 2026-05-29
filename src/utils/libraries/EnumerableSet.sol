// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title EnumerableSet
/// @notice Generic enumerable sets with O(1) add, remove, contains, length, at.
///         Backed by an array plus a 1-based index map (swap-and-pop on removal).
/// @dev Storage layout, error semantics, and method names match OpenZeppelin's
///      `utils/structs/EnumerableSet.sol`. No own ERC-7201 slot — `Set` is held
///      inline in the consumer's storage.
library EnumerableSet {
    struct Set {
        bytes32[] _values;
        mapping(bytes32 value => uint256 position) _positions; // 1-based; 0 = absent
    }

    struct AddressSet {
        Set _inner;
    }

    struct Bytes32Set {
        Set _inner;
    }

    struct UintSet {
        Set _inner;
    }

    // ---- Internal core operating on `Set` directly ----

    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (set._positions[value] != 0) return false;
        set._values.push(value);
        set._positions[value] = set._values.length;
        return true;
    }

    function _remove(Set storage set, bytes32 value) private returns (bool) {
        uint256 position = set._positions[value];
        if (position == 0) return false;
        uint256 lastIndex = set._values.length - 1;
        uint256 valueIndex = position - 1;
        if (valueIndex != lastIndex) {
            bytes32 lastValue = set._values[lastIndex];
            set._values[valueIndex] = lastValue;
            set._positions[lastValue] = position;
        }
        set._values.pop();
        delete set._positions[value];
        return true;
    }

    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._positions[value] != 0;
    }

    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        return set._values[index];
    }

    function _values(Set storage set) private view returns (bytes32[] memory) {
        return set._values;
    }

    // ---- Typed wrappers: Bytes32Set ----

    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _add(set._inner, value);
    }

    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _remove(set._inner, value);
    }

    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return _contains(set._inner, value);
    }

    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        return _at(set._inner, index);
    }

    function values(Bytes32Set storage set) internal view returns (bytes32[] memory) {
        return _values(set._inner);
    }

    // ---- Typed wrappers: AddressSet ----

    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(uint160(value))));
    }

    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(uint160(value))));
    }

    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(uint160(value))));
    }

    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint160(uint256(_at(set._inner, index))));
    }

    function values(AddressSet storage set) internal view returns (address[] memory result) {
        bytes32[] memory raw = _values(set._inner);
        assembly ("memory-safe") {
            result := raw
        }
    }

    // ---- Typed wrappers: UintSet ----

    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    function at(UintSet storage set, uint256 index) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
    }

    function values(UintSet storage set) internal view returns (uint256[] memory result) {
        bytes32[] memory raw = _values(set._inner);
        assembly ("memory-safe") {
            result := raw
        }
    }
}
