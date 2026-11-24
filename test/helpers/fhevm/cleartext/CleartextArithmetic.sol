// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {FheType} from "../fhevm-host/contracts/shared/FheType.sol";
import {FheTypeBitWidth} from "./FheTypeBitWidth.sol";

/**
 * @title CleartextArithmetic
 * @notice Pure arithmetic helpers used by cleartext execution mocks to mirror FHE bit-width semantics.
 */
library CleartextArithmetic {
    /**
     * @notice Clamps a value to the provided bit width using a low-bit mask.
     * @param value Value to clamp.
     * @param bitWidth Number of low bits to keep. Values >= 256 leave the value unchanged.
     * @return The masked value constrained to `bitWidth`.
     */
    function clamp(uint256 value, uint256 bitWidth) internal pure returns (uint256) {
        if (bitWidth >= 256) {
            return value;
        }

        return value & ((uint256(1) << bitWidth) - 1);
    }

    /// @notice Normalizes plaintext that is being stored as a typed ciphertext value.
    /// @dev Bool matches `trivial_encrypt_be_bytes`: only the least-significant byte matters.
    function normalizePlaintextToType(uint256 value, uint8 fheType) internal pure returns (uint256) {
        if (fheType == uint8(FheType.Bool)) {
            // forge-lint: disable-next-line(unsafe-typecast)
            return uint8(value) > 0 ? 1 : 0;
        }

        return clamp(value, FheTypeBitWidth.bitWidthForType(fheType));
    }

    /// @notice Normalizes a scalar RHS for mixed ciphertext-scalar operations.
    /// @dev Bool matches `arr_non_zero`: any non-zero byte in the scalar makes it `true`.
    function normalizeScalarToType(uint256 value, uint8 fheType) internal pure returns (uint256) {
        if (fheType == uint8(FheType.Bool)) {
            return value == 0 ? 0 : 1;
        }

        return clamp(value, FheTypeBitWidth.bitWidthForType(fheType));
    }

    function add(uint256 a, uint256 b, uint256 bitWidth) internal pure returns (uint256) {
        unchecked {
            return clamp(a + b, bitWidth);
        }
    }

    /**
     * @notice Subtracts `b` from `a` using wrap-around semantics at the provided bit width.
     * @param a Minuend value.
     * @param b Subtrahend value.
     * @param bitWidth Bit width of the simulated ciphertext type.
     * @return Wrapped subtraction result constrained to `bitWidth`.
     */
    function sub(uint256 a, uint256 b, uint256 bitWidth) internal pure returns (uint256) {
        unchecked {
            if (bitWidth >= 256) {
                return a - b;
            }
            return clamp(a - b + (uint256(1) << bitWidth), bitWidth);
        }
    }

    function mul(uint256 a, uint256 b, uint256 bitWidth) internal pure returns (uint256) {
        unchecked {
            return clamp(a * b, bitWidth);
        }
    }

    function bitAnd(uint256 a, uint256 b, uint256 bitWidth) internal pure returns (uint256) {
        return clamp(a & b, bitWidth);
    }

    function bitOr(uint256 a, uint256 b, uint256 bitWidth) internal pure returns (uint256) {
        return clamp(a | b, bitWidth);
    }

    function bitXor(uint256 a, uint256 b, uint256 bitWidth) internal pure returns (uint256) {
        return clamp(a ^ b, bitWidth);
    }

    function shl(uint256 a, uint256 b, uint256 bitWidth) internal pure returns (uint256) {
        return clamp(a << (b % bitWidth), bitWidth);
    }

    function shr(uint256 a, uint256 b, uint256 bitWidth) internal pure returns (uint256) {
        return clamp(a >> (b % bitWidth), bitWidth);
    }

    function rotl(uint256 a, uint256 b, uint256 bitWidth) internal pure returns (uint256) {
        uint256 shift = b % bitWidth;
        if (shift == 0) {
            return a;
        }
        return clamp((a << shift) | (a >> (bitWidth - shift)), bitWidth);
    }

    function rotr(uint256 a, uint256 b, uint256 bitWidth) internal pure returns (uint256) {
        uint256 shift = b % bitWidth;
        if (shift == 0) {
            return a;
        }
        return clamp((a >> shift) | (a << (bitWidth - shift)), bitWidth);
    }

    function neg(uint256 value, uint256 bitWidth) internal pure returns (uint256) {
        unchecked {
            return clamp(~value + 1, bitWidth);
        }
    }

    function bitNot(uint256 value, uint256 bitWidth) internal pure returns (uint256) {
        if (bitWidth >= 256) {
            return ~value;
        }
        uint256 mask = (uint256(1) << bitWidth) - 1;
        return ~value & mask;
    }

    function rand(bytes16 seed, uint256 bitWidth) internal pure returns (uint256) {
        uint256 randomValue = uint256(keccak256(abi.encodePacked(seed, "randValue")));
        return clamp(randomValue, bitWidth);
    }

    function randBounded(bytes16 seed, uint256 upperBound) internal pure returns (uint256) {
        uint256 randomValue = uint256(keccak256(abi.encodePacked(seed, "randBoundedValue")));
        return randomValue % upperBound;
    }

    // -----------------------------------------------------------------------
    // High-level FHE operation equivalents
    // Mirror the real coprocessor's tfhe-rs semantics:
    // - Encrypted operands are always in-range (guaranteed at storage time)
    // - Scalar operands are truncated to the target type's bit-width
    // - Modular arithmetic is applied via post-clamp where applicable
    //
    // Callers pass plaintext values read from their own storage.
    // For binary ops, `rhsRaw` should be `uint256(rhs)` when scalar,
    // or the stored plaintext when encrypted.
    // -----------------------------------------------------------------------

    /// @dev Resolve binary operands for an FHE operation.
    ///      Encrypted operands are assumed already in-range (guaranteed by trivialEncrypt,
    ///      verifyInput, and post-clamp on prior operations).
    ///      Scalar operands are truncated to the type's bit-width, matching the real
    ///      coprocessor's `to_be_uN_bit()` behavior.
    function _resolveBinaryOperands(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte)
        private
        pure
        returns (uint256 a, uint256 b, uint256 bw)
    {
        bw = FheTypeBitWidth.bitWidthForType(fheType);
        a = lhsRaw;
        b = (scalarByte == 0x01) ? normalizeScalarToType(rhsRaw, fheType) : rhsRaw;
    }

    // --- Binary arithmetic ---

    function fheAdd(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte) internal pure returns (uint256) {
        (uint256 a, uint256 b, uint256 bw) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return add(a, b, bw);
    }

    function fheSub(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte) internal pure returns (uint256) {
        (uint256 a, uint256 b, uint256 bw) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return sub(a, b, bw);
    }

    function fheMul(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte) internal pure returns (uint256) {
        (uint256 a, uint256 b, uint256 bw) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return mul(a, b, bw);
    }

    function fheDiv(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte) internal pure returns (uint256) {
        (uint256 a, uint256 b,) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return a / b;
    }

    function fheRem(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte) internal pure returns (uint256) {
        (uint256 a, uint256 b,) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return a % b;
    }

    // --- Binary bitwise ---

    function fheBitAnd(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte)
        internal
        pure
        returns (uint256)
    {
        (uint256 a, uint256 b, uint256 bw) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return bitAnd(a, b, bw);
    }

    function fheBitOr(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte)
        internal
        pure
        returns (uint256)
    {
        (uint256 a, uint256 b, uint256 bw) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return bitOr(a, b, bw);
    }

    function fheBitXor(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte)
        internal
        pure
        returns (uint256)
    {
        (uint256 a, uint256 b, uint256 bw) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return bitXor(a, b, bw);
    }

    // --- Shifts / rotates ---

    function fheShl(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte) internal pure returns (uint256) {
        (uint256 a, uint256 b, uint256 bw) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return shl(a, b, bw);
    }

    function fheShr(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte) internal pure returns (uint256) {
        (uint256 a, uint256 b, uint256 bw) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return shr(a, b, bw);
    }

    function fheRotl(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte) internal pure returns (uint256) {
        (uint256 a, uint256 b, uint256 bw) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return rotl(a, b, bw);
    }

    function fheRotr(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte) internal pure returns (uint256) {
        (uint256 a, uint256 b, uint256 bw) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return rotr(a, b, bw);
    }

    // --- Comparisons ---

    function fheEq(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte) internal pure returns (uint256) {
        (uint256 a, uint256 b,) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return (a == b) ? 1 : 0;
    }

    function fheNe(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte) internal pure returns (uint256) {
        (uint256 a, uint256 b,) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return (a != b) ? 1 : 0;
    }

    function fheGe(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte) internal pure returns (uint256) {
        (uint256 a, uint256 b,) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return (a >= b) ? 1 : 0;
    }

    function fheGt(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte) internal pure returns (uint256) {
        (uint256 a, uint256 b,) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return (a > b) ? 1 : 0;
    }

    function fheLe(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte) internal pure returns (uint256) {
        (uint256 a, uint256 b,) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return (a <= b) ? 1 : 0;
    }

    function fheLt(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte) internal pure returns (uint256) {
        (uint256 a, uint256 b,) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return (a < b) ? 1 : 0;
    }

    // --- Min / Max ---

    function fheMin(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte) internal pure returns (uint256) {
        (uint256 a, uint256 b,) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return (a < b) ? a : b;
    }

    function fheMax(uint256 lhsRaw, uint256 rhsRaw, uint8 fheType, bytes1 scalarByte) internal pure returns (uint256) {
        (uint256 a, uint256 b,) = _resolveBinaryOperands(lhsRaw, rhsRaw, fheType, scalarByte);
        return (a > b) ? a : b;
    }

    // --- Unary ---

    function fheNeg(uint256 valueRaw, uint8 fheType) internal pure returns (uint256) {
        uint256 bw = FheTypeBitWidth.bitWidthForType(fheType);
        return neg(valueRaw, bw);
    }

    function fheNot(uint256 valueRaw, uint8 fheType) internal pure returns (uint256) {
        uint256 bw = FheTypeBitWidth.bitWidthForType(fheType);
        return bitNot(valueRaw, bw);
    }

    // --- Special ---

    /// @dev The require is a guardrail, not a semantic check: all storage paths normalize bools,
    ///      and the real coprocessor's FheBool cannot carry a non-canonical payload.
    function fheIfThenElse(uint256 control, uint256 ifTrue, uint256 ifFalse) internal pure returns (uint256) {
        require(control == 0 || control == 1, "Unexpected FheIfThenElse control value");
        return (control == 1) ? ifTrue : ifFalse;
    }

    // @dev: While the host contracts disable casting to Bool (prefer using FheNe instead), the
    // internals should not be opinionated about it and mirror the coprocessor's behavior.
    function fheCast(uint256 valueRaw, uint8 toType) internal pure returns (uint256) {
        if (toType == uint8(FheType.Bool)) {
            return valueRaw > 0 ? 1 : 0;
        }
        return clamp(valueRaw, FheTypeBitWidth.bitWidthForType(toType));
    }
}
