// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IUniswapV3Pool
/// @author Modified from Uniswap V3 (https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/IUniswapV3Pool.sol
///         and .../interfaces/pool/IUniswapV3PoolDerivedState.sol)
/// @notice Minimal vendored subset of a Uniswap V3 pool, covering only what the Lattice
///         UniswapV3Adapter needs: the time-weighted `observe` oracle (the manipulation-resistant
///         valuation source), the immutable token/fee/tick-spacing readers, and `slot0` (declared
///         for completeness / tests — the adapter MUST NEVER value its position from `slot0` because
///         the spot tick is single-block manipulable).
/// @dev Vendored subset — do not add a uniswap-v3-core dependency. Valuation reads are `view`.
interface IUniswapV3Pool {
    /// @notice Returns cumulative tick and liquidity-in-range values as of each `secondsAgo`.
    /// @dev The TWAP arithmetic-mean tick over a window `w` is
    ///      `(tickCumulatives[0] - tickCumulatives[1]) / int56(uint56(w))` for
    ///      `secondsAgos = [w, 0]`. This is the canonical Uniswap V3 oracle and is the ONLY price
    ///      source the adapter uses for NAV — it is resistant to single-block manipulation because it
    ///      averages the tick over the whole window.
    /// @param secondsAgos From how long ago each cumulative value should be returned (seconds).
    /// @return tickCumulatives Cumulative tick values as of each `secondsAgos` from the current block.
    /// @return secondsPerLiquidityCumulativeX128s Cumulative seconds-per-liquidity-in-range values.
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);

    /// @notice The current pool state (slot0). **Manipulation hazard:** `sqrtPriceX96`/`tick` here are
    ///         the instantaneous spot price, settable within a single block by a flash swap. The
    ///         adapter declares this only so callers/tests can observe spot; it is NEVER used for NAV.
    /// @return sqrtPriceX96 The current price as a sqrt(token1/token0) Q64.96 value.
    /// @return tick The current tick.
    /// @return observationIndex The index of the last written observation.
    /// @return observationCardinality The current maximum number of observations stored.
    /// @return observationCardinalityNext The next maximum number of observations.
    /// @return feeProtocol The protocol fee for both tokens of the pool.
    /// @return unlocked Whether the pool is currently locked to reentrancy.
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );

    /// @notice The pool tick spacing (governs which ticks may be initialized; full-range positions use
    ///         the min/max usable ticks aligned to this spacing).
    function tickSpacing() external view returns (int24);

    /// @notice The first of the two tokens of the pool, sorted by address.
    function token0() external view returns (address);

    /// @notice The second of the two tokens of the pool, sorted by address.
    function token1() external view returns (address);

    /// @notice The pool's fee in hundredths of a bip (i.e. 1e-6).
    function fee() external view returns (uint24);
}
