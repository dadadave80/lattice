// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title UniswapV3FullRangeMath
/// @author Modified from Uniswap V3 — TickMath
///         (https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickMath.sol),
///         FullMath (https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/FullMath.sol),
///         and LiquidityAmounts
///         (https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/LiquidityAmounts.sol).
/// @notice Pure-math helpers the Lattice UniswapV3Adapter needs to value a **full-range** position
///         from a TWAP tick: `getSqrtRatioAtTick` (tick → sqrtPriceX96), `getAmountsForLiquidity`
///         (liquidity + price range → (amount0, amount1)), and `FullMath.mulDiv` (512-bit
///         intermediate, overflow-safe). Stateless utility library — no own storage, no facet, no
///         interface file (Lattice utility-library pattern).
/// @dev The original Uniswap libraries target Solidity 0.7/0.8 with explicit `unchecked` blocks; the
///      ports here preserve the exact arithmetic (wrapping is intentional and required for the magic
///      constants) inside `unchecked` so the bit-twiddling matches the canonical results. `MIN_TICK`
///      / `MAX_TICK` are the v3 tick bounds; a full-range position uses the min/max *usable* ticks
///      (these bounds floored/ceiled to the pool's `tickSpacing`), computed by the caller.
library UniswapV3FullRangeMath {
    /// @notice The minimum tick that may be used on any pool (TickMath.MIN_TICK).
    int24 internal constant MIN_TICK = -887272;
    /// @notice The maximum tick that may be used on any pool (TickMath.MAX_TICK).
    int24 internal constant MAX_TICK = 887272;

    /// @notice The minimum value `getSqrtRatioAtTick` can return (== getSqrtRatioAtTick(MIN_TICK)).
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    /// @notice The maximum value `getSqrtRatioAtTick` can return (== getSqrtRatioAtTick(MAX_TICK)).
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    /// @notice Thrown when a tick passed to `getSqrtRatioAtTick` is out of the v3 bounds.
    error TickOutOfBounds(int24 tick);

    /// @notice Calculates `sqrt(1.0001^tick) * 2^96` (a Q64.96 sqrt price) for the given tick.
    /// @dev Verbatim port of Uniswap V3 `TickMath.getSqrtRatioAtTick`. The chained conditional
    ///      multiplications reconstruct the fixed-point sqrt-ratio from the tick's set bits; the magic
    ///      constants and wrapping multiplies are exactly the v3 originals and MUST run unchecked.
    /// @param tick The tick to convert; must satisfy `MIN_TICK <= tick <= MAX_TICK`.
    /// @return sqrtPriceX96 The sqrt(token1/token0) ratio as a Q64.96 value.
    function getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
        unchecked {
            uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
            if (absTick > uint256(int256(MAX_TICK))) revert TickOutOfBounds(tick);

            uint256 ratio =
                absTick & 0x1 != 0 ? 0xfffcb933bd6fad37aa2d162d1a594001 : 0x100000000000000000000000000000000;
            if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
            if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
            if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
            if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
            if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
            if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
            if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
            if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
            if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
            if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
            if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
            if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
            if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
            if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
            if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
            if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
            if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
            if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
            if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

            if (tick > 0) ratio = type(uint256).max / ratio;

            // Downcast + round up: this divides by 2^32 and rounds up to get a Q64.96 value. We round up
            // because a tick is always the lower bound of the price range the sqrt ratio represents.
            sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
        }
    }

    /// @notice Multiplies `a * b` then divides by `denominator` with full 512-bit precision; reverts
    ///         on overflow of the final result or division by zero.
    /// @dev Verbatim port of Uniswap V3 `FullMath.mulDiv` (Remco Bloemen's 512-bit method). Needed
    ///      because intermediate products (e.g. `amount1 * 2^192`) overflow 256 bits.
    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply [prod1 prod0] = a * b.
            uint256 prod0;
            uint256 prod1;
            assembly {
                let mm := mulmod(a, b, not(0))
                prod0 := mul(a, b)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Handle non-overflow cases, 256 by 256 division.
            if (prod1 == 0) {
                require(denominator > 0, "mulDiv:0");
                assembly {
                    result := div(prod0, denominator)
                }
                return result;
            }

            // Make sure the result is less than 2**256. Also prevents denominator == 0.
            require(denominator > prod1, "mulDiv:OF");

            // 512 by 256 division.
            // Make division exact by subtracting the remainder from [prod1 prod0].
            uint256 remainder;
            assembly {
                remainder := mulmod(a, b, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator and compute the largest power of two divisor of
            // denominator. Always >= 1.
            uint256 twos = denominator & (~denominator + 1);
            assembly {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }

            prod0 |= prod1 * twos;

            // Invert denominator mod 2**256 via Newton-Raphson (4 bits → 256 bits in 6 doublings).
            uint256 inv = (3 * denominator) ^ 2;
            inv *= 2 - denominator * inv; // mod 2**8
            inv *= 2 - denominator * inv; // mod 2**16
            inv *= 2 - denominator * inv; // mod 2**32
            inv *= 2 - denominator * inv; // mod 2**64
            inv *= 2 - denominator * inv; // mod 2**128
            inv *= 2 - denominator * inv; // mod 2**256

            result = prod0 * inv;
            return result;
        }
    }

    /// @notice Computes the token0 amount for `liquidity` between two sqrt prices.
    /// @dev Port of Uniswap V3 `LiquidityAmounts.getAmount0ForLiquidity`. Assumes `sqrtA <= sqrtB`.
    function getAmount0ForLiquidity(uint160 sqrtA, uint160 sqrtB, uint128 liquidity)
        internal
        pure
        returns (uint256 amount0)
    {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        // amount0 = L * (sqrtB - sqrtA) / (sqrtA * sqrtB) * 2^96
        uint256 numerator1 = uint256(liquidity) << 96;
        uint256 numerator2 = uint256(sqrtB) - uint256(sqrtA);
        return mulDiv(mulDiv(numerator1, numerator2, sqrtB), 1, sqrtA);
    }

    /// @notice Computes the token1 amount for `liquidity` between two sqrt prices.
    /// @dev Port of Uniswap V3 `LiquidityAmounts.getAmount1ForLiquidity`. Assumes `sqrtA <= sqrtB`.
    function getAmount1ForLiquidity(uint160 sqrtA, uint160 sqrtB, uint128 liquidity)
        internal
        pure
        returns (uint256 amount1)
    {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        // amount1 = L * (sqrtB - sqrtA) / 2^96
        return mulDiv(uint256(liquidity), uint256(sqrtB) - uint256(sqrtA), 1 << 96);
    }

    /// @notice Computes (amount0, amount1) currently composing `liquidity` at the current sqrt price,
    ///         for a position spanning [sqrtLower, sqrtUpper].
    /// @dev Port of Uniswap V3 `LiquidityAmounts.getAmountsForLiquidity`. Three regimes:
    ///      - price below the range  → all token0;
    ///      - price inside the range → a split of both (the full-range, in-price case);
    ///      - price above the range  → all token1.
    /// @param sqrtCurrent The current sqrt price (Q64.96), e.g. derived from the TWAP tick.
    /// @param sqrtLower The sqrt price at the position's lower tick.
    /// @param sqrtUpper The sqrt price at the position's upper tick.
    /// @param liquidity The position's liquidity.
    function getAmountsForLiquidity(uint160 sqrtCurrent, uint160 sqrtLower, uint160 sqrtUpper, uint128 liquidity)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        if (sqrtLower > sqrtUpper) (sqrtLower, sqrtUpper) = (sqrtUpper, sqrtLower);
        if (sqrtCurrent <= sqrtLower) {
            amount0 = getAmount0ForLiquidity(sqrtLower, sqrtUpper, liquidity);
        } else if (sqrtCurrent < sqrtUpper) {
            amount0 = getAmount0ForLiquidity(sqrtCurrent, sqrtUpper, liquidity);
            amount1 = getAmount1ForLiquidity(sqrtLower, sqrtCurrent, liquidity);
        } else {
            amount1 = getAmount1ForLiquidity(sqrtLower, sqrtUpper, liquidity);
        }
    }

    /// @notice Computes the liquidity for a given token0 amount between two sqrt prices.
    /// @dev Port of Uniswap V3 `LiquidityAmounts.getLiquidityForAmount0`. Assumes `sqrtA <= sqrtB`.
    function getLiquidityForAmount0(uint160 sqrtA, uint160 sqrtB, uint256 amount0)
        internal
        pure
        returns (uint128 liquidity)
    {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        uint256 intermediate = mulDiv(uint256(sqrtA), uint256(sqrtB), 1 << 96);
        return uint128(mulDiv(amount0, intermediate, uint256(sqrtB) - uint256(sqrtA)));
    }

    /// @notice Computes the liquidity for a given token1 amount between two sqrt prices.
    /// @dev Port of Uniswap V3 `LiquidityAmounts.getLiquidityForAmount1`. Assumes `sqrtA <= sqrtB`.
    function getLiquidityForAmount1(uint160 sqrtA, uint160 sqrtB, uint256 amount1)
        internal
        pure
        returns (uint128 liquidity)
    {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        return uint128(mulDiv(amount1, 1 << 96, uint256(sqrtB) - uint256(sqrtA)));
    }

    /// @notice Computes the maximum liquidity for `(amount0, amount1)` at the current sqrt price over
    ///         the range [sqrtLower, sqrtUpper] (the liquidity actually mintable from both amounts).
    /// @dev Port of Uniswap V3 `LiquidityAmounts.getLiquidityForAmounts`. In-range (the full-range,
    ///      in-price case) takes the binding minimum of the two single-token liquidities.
    function getLiquidityForAmounts(
        uint160 sqrtCurrent,
        uint160 sqrtLower,
        uint160 sqrtUpper,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtLower > sqrtUpper) (sqrtLower, sqrtUpper) = (sqrtUpper, sqrtLower);
        if (sqrtCurrent <= sqrtLower) {
            liquidity = getLiquidityForAmount0(sqrtLower, sqrtUpper, amount0);
        } else if (sqrtCurrent < sqrtUpper) {
            uint128 liquidity0 = getLiquidityForAmount0(sqrtCurrent, sqrtUpper, amount0);
            uint128 liquidity1 = getLiquidityForAmount1(sqrtLower, sqrtCurrent, amount1);
            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = getLiquidityForAmount1(sqrtLower, sqrtUpper, amount1);
        }
    }

    /// @notice Returns the min/max *usable* ticks for a full-range position on a pool with the given
    ///         `tickSpacing` (the v3 tick bounds floored/ceiled to a multiple of `tickSpacing`).
    /// @param tickSpacing The pool's tick spacing (must be > 0).
    /// @return tickLower The lowest initializable tick (full-range lower bound).
    /// @return tickUpper The highest initializable tick (full-range upper bound).
    function fullRangeTicks(int24 tickSpacing) internal pure returns (int24 tickLower, int24 tickUpper) {
        // Truncating integer division toward zero gives the magnitude; multiply back to align.
        tickLower = (MIN_TICK / tickSpacing) * tickSpacing;
        tickUpper = (MAX_TICK / tickSpacing) * tickSpacing;
    }

    /// @notice Values a sqrt-priced `(amount0, amount1)` pair in token0 units at price `sqrtPriceX96`.
    /// @dev token1→token0 conversion: the pool price is `token1/token0 = sqrtPriceX96^2 / 2^192`, so
    ///      `amount1` (token1 units) is worth `amount1 * 2^192 / sqrtPriceX96^2` in token0 units. Done
    ///      in two `mulDiv` steps so the `* 2^96` factors never overflow.
    /// @param amount0 The token0 amount (already in token0 units).
    /// @param amount1 The token1 amount to convert to token0 units.
    /// @param sqrtPriceX96 The sqrt price (Q64.96) to value at.
    /// @return value0 `amount0 + (amount1 valued in token0)`.
    function valueInToken0(uint256 amount0, uint256 amount1, uint160 sqrtPriceX96)
        internal
        pure
        returns (uint256 value0)
    {
        uint256 q96 = 1 << 96;
        // amount1 * 2^192 / sqrtP^2 = (amount1 * 2^96 / sqrtP) * 2^96 / sqrtP, each step overflow-safe.
        uint256 step1 = mulDiv(amount1, q96, sqrtPriceX96);
        uint256 amount1InToken0 = mulDiv(step1, q96, sqrtPriceX96);
        return amount0 + amount1InToken0;
    }
}
