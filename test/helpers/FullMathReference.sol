// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title FullMathReference
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only oracle for 512-bit `x * y / d`, written to share nothing with the `src` `mulDiv` ports: the
///         product is built from 128-bit limbs in checked arithmetic (no `mulmod` CRT trick), and the quotient comes
///         from bit-by-bit long division over all 512 bits (no modular inverse). The overflow verdict is read off the
///         full 512-bit quotient, so it does not reuse the ports' `high < d` shortcut either. Slow by design.
library FullMathReference {
    uint256 internal constant MASK128 = type(uint128).max;

    /// @notice The 512-bit product `x * y = hi * 2^256 + lo`.
    function mul512(uint256 x, uint256 y) internal pure returns (uint256 hi, uint256 lo) {
        uint256 x0 = x & MASK128;
        uint256 x1 = x >> 128;
        uint256 y0 = y & MASK128;
        uint256 y1 = y >> 128;

        uint256 p00 = x0 * y0;
        uint256 p01 = x0 * y1;
        uint256 p10 = x1 * y0;
        uint256 p11 = x1 * y1;

        // The middle column: the high half of p00 plus the low halves of the cross terms (< 3 * 2^128).
        uint256 mid = (p00 >> 128) + (p01 & MASK128) + (p10 & MASK128);
        lo = (p00 & MASK128) | ((mid & MASK128) << 128);
        hi = p11 + (p01 >> 128) + (p10 >> 128) + (mid >> 128);
    }

    /// @notice The 512-bit sum of a 512-bit value and a 256-bit value; `ok` is false if it exceeds 512 bits.
    function add512(uint256 hi, uint256 lo, uint256 b) internal pure returns (bool ok, uint256 sumHi, uint256 sumLo) {
        unchecked {
            sumLo = lo + b;
            uint256 carry = sumLo < lo ? 1 : 0;
            sumHi = hi + carry;
            ok = sumHi >= hi;
        }
    }

    /// @notice Long division of the 512-bit `[hi lo]` by a non-zero `d`: returns the 512-bit quotient and remainder.
    function divRem512(uint256 hi, uint256 lo, uint256 d)
        internal
        pure
        returns (uint256 qHi, uint256 qLo, uint256 rem)
    {
        require(d != 0, "FullMathReference: d == 0");
        unchecked {
            for (uint256 i = 512; i > 0;) {
                --i;
                uint256 bit = i >= 256 ? (hi >> (i - 256)) & 1 : (lo >> i) & 1;
                // `rem < d < 2^256`, so the shifted remainder needs at most 257 bits; `carry` is the 257th.
                uint256 carry = rem >> 255;
                rem = (rem << 1) | bit;
                if (carry == 1 || rem >= d) {
                    // With the carry set the true value is `rem + 2^256 >= d`; the wrapping subtraction is exact.
                    rem -= d;
                    if (i >= 256) qHi |= 1 << (i - 256);
                    else qLo |= 1 << i;
                }
            }
        }
    }

    /// @notice `x * y / d` rounded down (or up when `roundUp`), with `ok == false` wherever the exact result does not
    ///         fit a uint256 or `d == 0` — the domain in which a faithful `mulDiv` must revert.
    function mulDiv(uint256 x, uint256 y, uint256 d, bool roundUp) internal pure returns (bool ok, uint256 result) {
        if (d == 0) return (false, 0);
        (uint256 hi, uint256 lo) = mul512(x, y);
        (uint256 qHi, uint256 qLo, uint256 rem) = divRem512(hi, lo, d);
        if (qHi != 0) return (false, 0);
        if (roundUp && rem != 0) {
            if (qLo == type(uint256).max) return (false, 0);
            return (true, qLo + 1);
        }
        return (true, qLo);
    }
}
