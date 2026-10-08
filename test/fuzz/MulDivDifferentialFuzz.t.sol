// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FullMathReference} from "@lattice-test/helpers/FullMathReference.sol";
import {Math} from "@lattice/utils/libraries/math/Math.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Exposes `Math.mulDiv` (and `Math.mul512`, which it builds on) as external calls, so a test can observe
///         its result or revert data.
contract MulDivHarness {
    function mathMulDiv(uint256 x, uint256 y, uint256 d) external pure returns (uint256) {
        return Math.mulDiv(x, y, d);
    }

    function mathMulDivRounding(uint256 x, uint256 y, uint256 d, Math.Rounding r) external pure returns (uint256) {
        return Math.mulDiv(x, y, d, r);
    }

    function mul512(uint256 a, uint256 b) external pure returns (uint256 high, uint256 low) {
        return Math.mul512(a, b);
    }
}

/// @title MulDivDifferentialFuzz
/// @notice Differential tests for `Math.mulDiv` (OpenZeppelin v5.6), the one `mulDiv` in `src`: ERC-4626 share
///         pricing (`ERC4626Lib`) and the Uniswap V3 position math (`UniswapV3FullRangeMath`, `UniswapV3AdapterLib`)
///         call it in place of their former OpenZeppelin v5.1 and Uniswap V3 `FullMath` copies (#246). It is checked
///         against {FullMathReference}, an independent 512-bit oracle. Every run checks, for every rounding mode:
///         - the revert domain: it reverts exactly when the exact quotient does not fit a uint256 or `d == 0`;
///         - the result: floor and ceil match the oracle, and `q * d + (x * y mod d) == x * y` in 512 bits;
///         - the revert data: `Panic(0x12)` for `d == 0`, otherwise `Panic(0x11)`. Of the removed copies, the
///           ERC-4626 one differed only on its 512-bit path (`d <= high`, incl. 0), where it raised
///           `IERC4626.MathOverflowedMulDiv()`; the Uniswap V3 port raised `Error("mulDiv:0")` / `Error("mulDiv:OF")`.
///         Inputs are shaped so each branch is driven on purpose: the `high == 0` fast path, the 512-bit success
///         path (`d > high`), the 512-bit overflow path (`d <= high`) and the ceil `+1` overflow at a `max` floor.
contract MulDivDifferentialFuzz is Test {
    uint256 internal constant MAX = type(uint256).max;

    MulDivHarness internal h;

    function setUp() public {
        h = new MulDivHarness();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                FUZZ TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Unconstrained operands: almost every product needs 512 bits, so this mostly drives overflow reverts.
    /// forge-config: default.fuzz.runs = 512
    function testFuzz_MulDiv_RandomOperands(uint256 x, uint256 y, uint256 d) public view {
        _assertMulDiv(x, y, d);
    }

    /// @notice 128-bit operands keep the product in 256 bits: the `high == 0` fast path, including `d == 0`.
    function testFuzz_MulDiv_FastPath(uint128 x, uint128 y, uint256 d) public view {
        (uint256 hi,) = FullMathReference.mul512(x, y);
        assertEq(hi, 0, "product fits 256 bits");
        _assertMulDiv(x, y, d);
    }

    /// @notice A 512-bit product over a denominator above its high word: the full-precision success path.
    /// forge-config: default.fuzz.runs = 1024
    function testFuzz_MulDiv_FullPrecisionPath(uint256 x, uint256 y, uint256 d) public view {
        (uint256 hi,) = FullMathReference.mul512(x, y);
        vm.assume(hi != 0);
        d = bound(d, hi + 1, MAX);

        (bool ok,) = FullMathReference.mulDiv(x, y, d, false);
        assertTrue(ok, "quotient fits 256 bits");
        _assertMulDiv(x, y, d);
    }

    /// @notice A 512-bit product with a small 512-bit-path operand pair, so the denominator spans every width.
    function testFuzz_MulDiv_FullPrecisionPathSmallDenominator(uint256 x, uint8 shift, uint256 d) public view {
        // y = 2^shift + 1 keeps `high` below 2^shift, so a denominator in (high, 2^shift] is a narrow one.
        uint256 y = (uint256(1) << shift) + 1;
        (uint256 hi,) = FullMathReference.mul512(x, y);
        vm.assume(hi != 0 && hi < uint256(1) << shift);
        d = bound(d, hi + 1, uint256(1) << shift);
        _assertMulDiv(x, y, d);
    }

    /// @notice A 512-bit product over a denominator at or below its high word (incl. 0): `mulDiv` must revert.
    function testFuzz_MulDiv_OverflowReverts(uint256 x, uint256 y, uint256 d) public view {
        (uint256 hi,) = FullMathReference.mul512(x, y);
        vm.assume(hi != 0);
        d = bound(d, 0, hi);

        (bool ok,) = FullMathReference.mulDiv(x, y, d, false);
        assertFalse(ok, "quotient overflows");
        _assertMulDiv(x, y, d);
    }

    /// @notice `x * y == q * d` exactly: floor and ceil agree, for any quotient and denominator.
    function testFuzz_MulDiv_ExactQuotient(uint256 q, uint256 d) public view {
        d = bound(d, 1, MAX);
        (bool ok, uint256 floor_) = FullMathReference.mulDiv(q, d, d, false);
        assertTrue(ok && floor_ == q, "exact quotient");
        _assertMulDiv(q, d, d);
    }

    /// @notice Floor is exactly `type(uint256).max` with a non-zero remainder, so only the ceil `+1` overflows.
    /// @dev `x * y = max * (y - 1) + r` with `r = max mod y`, `x = max - (max - r) / y` and `d = y - 1 > r`.
    function testFuzz_MulDiv_CeilOverflowsAtMaxFloor(uint256 y) public view {
        y = bound(y, 3, MAX);
        uint256 r = MAX % y;
        vm.assume(r != 0 && r < y - 1);
        uint256 x = MAX - (MAX - r) / y;
        uint256 d = y - 1;

        (bool okFloor, uint256 floor_) = FullMathReference.mulDiv(x, y, d, false);
        (bool okCeil,) = FullMathReference.mulDiv(x, y, d, true);
        assertTrue(okFloor && floor_ == MAX, "floor is max");
        assertFalse(okCeil, "ceil overflows");
        _assertMulDiv(x, y, d);
    }

    /// @notice `Math.mul512` (the CRT 512-bit product `mulDiv` builds on) equals the limb-wise product.
    function testFuzz_Mul512MatchesLimbProduct(uint256 a, uint256 b) public view {
        (uint256 hi, uint256 lo) = FullMathReference.mul512(a, b);
        (uint256 high, uint256 low) = h.mul512(a, b);
        assertEq(high, hi, "mul512 high");
        assertEq(low, lo, "mul512 low");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               EDGE VALUES
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Hand-picked edges: zero operands, `max` operands, and denominators 0, 1, 2 and `max`.
    function test_MulDiv_EdgeValues() public view {
        uint256[3][22] memory cases = [
            [uint256(0), 0, 0], // 0 / 0
            [uint256(0), 0, 1],
            [uint256(0), MAX, MAX],
            [MAX, 0, 1],
            [uint256(1), 1, 0], // fast path, d == 0
            [MAX, MAX, 0], // 512-bit path, d == 0
            [MAX, 1, 1], // max / 1
            [MAX, 1, MAX], // 1
            [uint256(1), 1, MAX], // 0, ceil 1
            [MAX, MAX, MAX], // max, 512-bit path
            [MAX, MAX, MAX - 1], // overflows by one
            [MAX, MAX, 1], // overflows
            [MAX, MAX - 1, MAX], // max - 1, exact
            [MAX, 2, 2], // max, 512-bit path with d == 2
            [MAX, 3, 2], // overflows
            [uint256(1) << 255, 2, 1], // 2^256 / 1 overflows
            [uint256(1) << 255, 2, 2], // 2^255
            [uint256(1) << 255, 4, 3], // floor(2^257 / 3), ceil rounds up
            [uint256(1) << 128, uint256(1) << 128, (uint256(1) << 128) + 1], // high == 1, odd denominator
            [MAX, MAX, uint256(1) << 255], // even denominator, overflows
            [MAX, MAX - 2, MAX - 1], // near-max quotient, odd numerator
            [MAX - 1, MAX - 1, MAX] // near-max quotient, odd denominator
        ];
        for (uint256 i; i < cases.length; ++i) {
            _assertMulDiv(cases[i][0], cases[i][1], cases[i][2]);
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Compares every rounding mode on `(x, y, d)` against the oracle, including revert data.
    function _assertMulDiv(uint256 x, uint256 y, uint256 d) internal view {
        (bool okFloor, uint256 floor_) = FullMathReference.mulDiv(x, y, d, false);
        (bool okCeil, uint256 ceil_) = FullMathReference.mulDiv(x, y, d, true);
        if (okFloor) _assertIdentity(x, y, d, floor_);

        // Floor revert data: Math panics like checked arithmetic, on both the 256-bit and the 512-bit path.
        bytes memory err = _panic(d == 0 ? 0x12 : 0x11);

        _assertCall(abi.encodeCall(h.mathMulDiv, (x, y, d)), okFloor, floor_, err, "Math");
        _assertCall(
            abi.encodeCall(h.mathMulDivRounding, (x, y, d, Math.Rounding.Floor)), okFloor, floor_, err, "Math.Floor"
        );
        _assertCall(
            abi.encodeCall(h.mathMulDivRounding, (x, y, d, Math.Rounding.Trunc)), okFloor, floor_, err, "Math.Trunc"
        );

        // Ceil: a floor revert propagates unchanged; otherwise only the checked `+1` can overflow.
        if (okFloor) err = _panic(0x11);
        _assertCall(
            abi.encodeCall(h.mathMulDivRounding, (x, y, d, Math.Rounding.Ceil)), okCeil, ceil_, err, "Math.Ceil"
        );
        _assertCall(
            abi.encodeCall(h.mathMulDivRounding, (x, y, d, Math.Rounding.Expand)), okCeil, ceil_, err, "Math.Expand"
        );
    }

    /// @dev Asserts one call reverts exactly when the oracle does, then its result or its revert data.
    function _assertCall(
        bytes memory data,
        bool expectOk,
        uint256 expected,
        bytes memory expectedErr,
        string memory label
    ) internal view {
        (bool ok, bytes memory ret) = address(h).staticcall(data);
        assertEq(ok, expectOk, string.concat(label, ": revert domain differs from the reference"));
        if (ok) assertEq(abi.decode(ret, (uint256)), expected, string.concat(label, ": result differs"));
        else assertEq(ret, expectedErr, string.concat(label, ": revert data"));
    }

    /// @dev `q * d + (x * y mod d) == x * y`, all in 512 bits, with the remainder below `d`.
    function _assertIdentity(uint256 x, uint256 y, uint256 d, uint256 q) internal pure {
        uint256 rem = mulmod(x, y, d);
        assertLt(rem, d, "remainder below denominator");
        (uint256 qdHi, uint256 qdLo) = FullMathReference.mul512(q, d);
        (bool ok, uint256 sumHi, uint256 sumLo) = FullMathReference.add512(qdHi, qdLo, rem);
        (uint256 hi, uint256 lo) = FullMathReference.mul512(x, y);
        assertTrue(ok, "q * d + r fits 512 bits");
        assertEq(sumHi, hi, "identity high word");
        assertEq(sumLo, lo, "identity low word");
    }

    function _panic(uint256 code) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("Panic(uint256)", code);
    }
}
