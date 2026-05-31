// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev A ShortString is a string packed into a single bytes32 word.
/// The lower byte stores the byte length of the string (0-31).
/// Strings of 32 bytes or more must use the fallback (storage) mechanism.
type ShortString is bytes32;

/// @title ShortStrings
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ShortStrings.sol)
/// @notice Pack strings of up to 31 bytes into a single bytes32 word.
/// @dev Mirrors OpenZeppelin's ShortStrings. Strings longer than 31 bytes
///      fall back to a `string storage` variable held by the caller.
///      The sentinel value for a fallback ShortString is bytes32(type(uint256).max)
///      (all 0xff), which cannot be a valid packed short string since the length
///      byte would be 255 — greater than 31.
library ShortStrings {
    /// @dev Sentinel for a ShortString stored in the fallback slot.
    bytes32 private constant FALLBACK_SENTINEL = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    error StringTooLong(string str);
    error InvalidShortString();

    /// @notice Packs a string of up to 31 bytes into a ShortString.
    /// @dev Reverts with {StringTooLong} if the string is 32 bytes or longer.
    /// @param str The string to pack.
    /// @return The packed ShortString.
    function toShortString(string memory str) internal pure returns (ShortString) {
        bytes memory bstr = bytes(str);
        if (bstr.length > 31) {
            revert StringTooLong(str);
        }
        return ShortString.wrap(_pack(bstr));
    }

    /// @notice Unpacks a ShortString into a string.
    /// @dev Reverts with {InvalidShortString} if the ShortString is the fallback sentinel.
    /// @param sstr The ShortString to unpack.
    /// @return The original string.
    function toString(ShortString sstr) internal pure returns (string memory) {
        uint256 len = byteLength(sstr);
        bytes32 raw = ShortString.unwrap(sstr);
        // Extract the data bytes (upper 31 bytes of the word)
        string memory str = new string(32);
        assembly ("memory-safe") {
            mstore(str, len)
            mstore(add(str, 0x20), raw)
        }
        return str;
    }

    /// @notice Returns the byte length of a ShortString.
    /// @dev The length is stored in the lowest byte of the packed word.
    ///      Reverts with {InvalidShortString} if the ShortString is the fallback sentinel.
    /// @param sstr The ShortString.
    /// @return The byte length.
    function byteLength(ShortString sstr) internal pure returns (uint256) {
        bytes32 raw = ShortString.unwrap(sstr);
        if (raw == FALLBACK_SENTINEL) {
            revert InvalidShortString();
        }
        // length is in the lowest byte
        return uint256(raw) & 0xff;
    }

    /// @notice Converts a string to a ShortString, falling back to storage for long strings.
    /// @dev If the string is longer than 31 bytes, it is stored in `store` and the
    ///      fallback sentinel is returned. Otherwise, the packed ShortString is returned
    ///      and `store` is left unchanged (but is assigned to empty to satisfy the compiler).
    /// @param value The string to convert.
    /// @param store A storage reference to use for strings that are too long.
    /// @return The ShortString (may be the fallback sentinel).
    function toShortStringWithFallback(string memory value, string storage store) internal returns (ShortString) {
        if (bytes(value).length < 32) {
            return toShortString(value);
        }
        // Store the full string in the storage fallback slot using assembly
        bytes memory bvalue = bytes(value);
        uint256 len = bvalue.length;
        assembly ("memory-safe") {
            let storeSlot := store.slot
            // Encode as long string: length*2+1 in the base slot, data in keccak(slot)
            sstore(storeSlot, add(mul(len, 2), 1))
            let dataSlot := keccak256(add(mload(0x40), 0), 32)
            // compute keccak256(storeSlot) for data start
            mstore(0x00, storeSlot)
            dataSlot := keccak256(0x00, 0x20)
            let words := div(add(len, 31), 32)
            for { let i := 0 } lt(i, words) { i := add(i, 1) } {
                sstore(add(dataSlot, i), mload(add(add(bvalue, 0x20), mul(i, 32))))
            }
        }
        return ShortString.wrap(FALLBACK_SENTINEL);
    }

    /// @notice Converts a ShortString back to a string, using storage fallback if needed.
    /// @param value The ShortString to convert.
    /// @param store The storage fallback that may contain the full string.
    /// @return The original string.
    function toStringWithFallback(ShortString value, string storage store) internal pure returns (string memory) {
        if (ShortString.unwrap(value) != FALLBACK_SENTINEL) {
            return toString(value);
        }
        return store;
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /// @dev Packs bytes into the upper bytes of a bytes32 word, length in the lowest byte.
    function _pack(bytes memory bstr) private pure returns (bytes32 result) {
        uint256 len = bstr.length;
        assembly ("memory-safe") {
            // Load 32 bytes starting at bstr data pointer; top-align them
            result := mload(add(bstr, 0x20))
        }
        // Mask out anything below the length byte and insert the length
        // Upper 31 bytes = string data; lowest byte = length
        result = (result & ~bytes32(uint256(0xff))) | bytes32(len);
    }
}
