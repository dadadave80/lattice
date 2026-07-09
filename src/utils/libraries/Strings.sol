// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title Strings
/// @author Vendored minimal subset of OpenZeppelin Contracts v5.6.1
///         (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/utils/Strings.sol).
///         Upstream is MIT. Only the address→hex helpers and the decimal `toString` are re-declared (the full
///         Strings lib pulls in Math/SignedMath/Bytes; `toString` is re-implemented Math-free). Vendored
///         subset — do not add an openzeppelin-contracts dependency.
/// @notice Address-to-string and uint-to-decimal-string helpers, incl. EIP-55 checksummed hex (needed by
///         gateway adapters that address remote contracts or chains by string, e.g. Axelar names and
///         Hyperbridge `EVM-<chainId>` state machine ids).
library Strings {
    bytes16 private constant HEX_DIGITS = "0123456789abcdef";
    uint8 private constant ADDRESS_LENGTH = 20;

    /// @dev `toHexString` was given a `length` too short for `value`.
    error StringsInsufficientHexLength(uint256 value, uint256 length);

    /// @notice Converts a `uint256` to its ASCII decimal string.
    /// @dev Math-free re-implementation (upstream sizes the buffer via `Math.log10`); two passes — count the
    ///      digits, then fill the buffer least-significant first.
    function toString(uint256 value) internal pure returns (string memory) {
        uint256 digits = 1;
        for (uint256 probe = value / 10; probe != 0; probe /= 10) {
            ++digits;
        }
        bytes memory buffer = new bytes(digits);
        for (uint256 i = digits; i > 0; --i) {
            buffer[i - 1] = HEX_DIGITS[value % 10];
            value /= 10;
        }
        return string(buffer);
    }

    /// @notice Converts a `uint256` to its ASCII hex string with fixed `length` (bytes), `0x`-prefixed.
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        uint256 localValue = value;
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = HEX_DIGITS[localValue & 0xf];
            localValue >>= 4;
        }
        if (localValue != 0) {
            revert StringsInsufficientHexLength(value, length);
        }
        return string(buffer);
    }

    /// @notice Converts an `address` to its (not checksummed) 20-byte ASCII hex string.
    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), ADDRESS_LENGTH);
    }

    /// @notice Converts an `address` to its EIP-55 checksummed ASCII hex string.
    function toChecksumHexString(address addr) internal pure returns (string memory) {
        bytes memory buffer = bytes(toHexString(addr));

        // hash the hex part of buffer (skip length + 2 bytes, length 40)
        uint256 hashValue;
        assembly ("memory-safe") {
            hashValue := shr(96, keccak256(add(buffer, 0x22), 40))
        }

        for (uint256 i = 41; i > 1; --i) {
            // possible values for buffer[i] are 48 (0) to 57 (9) and 97 (a) to 102 (f)
            if (hashValue & 0xf > 7 && uint8(buffer[i]) > 96) {
                // case shift by xoring with 0x20
                buffer[i] ^= 0x20;
            }
            hashValue >>= 4;
        }
        return string(buffer);
    }
}
