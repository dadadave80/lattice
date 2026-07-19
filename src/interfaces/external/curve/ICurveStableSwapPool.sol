// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ICurveStableSwapPool
/// @author Modified from Curve StableSwap (https://github.com/curvefi/curve-contract/blob/master/contracts/pool-templates/base/SwapTemplateBase.vy)
/// @notice Minimal vendored subset of a Curve StableSwap pool, specialized to a **2-coin** pool.
/// @dev Curve pools are generated per-N (the coins array is fixed-size in the Vyper source), so a
///      single Solidity signature must pin N. The Lattice Curve adapter targets the dominant
///      2-coin StableSwap shape (e.g. stETH/ETH, FRAX/USDC, USDe/USDC); the adapter supplies one
///      side via a configured `coinIndex` (0 or 1) and leaves the other at zero. Only the selectors
///      the adapter calls are declared. Methods that move funds are non-`view`; valuation reads are
///      `view`. NOTE: `get_virtual_price()` is **read-only-reentrancy-exposed** on real pools — see
///      `CurveStableSwapAdapterLib.totalAssetsManaged` for how the adapter avoids reading it mid
///      external interaction.
interface ICurveStableSwapPool {
    /// @notice Deposits `amounts` (indexed by coin) and mints at least `minMint` LP tokens to caller.
    /// @param amounts  Per-coin deposit amounts (the adapter sets only its `coinIndex` slot).
    /// @param minMint  Minimum LP to mint (slippage floor); reverts if the pool would mint less.
    /// @return minted  The amount of LP tokens minted to the caller.
    function add_liquidity(uint256[2] calldata amounts, uint256 minMint) external returns (uint256 minted);

    /// @notice Burns `lp` LP tokens and withdraws a single coin `i`, sending at least `minOut`.
    /// @param lp      LP token amount to burn.
    /// @param i       Coin index to receive (int128 per Curve ABI).
    /// @param minOut  Minimum coin out (slippage floor); reverts if the pool would return less.
    /// @return out    The amount of coin `i` returned to the caller.
    function remove_liquidity_one_coin(uint256 lp, int128 i, uint256 minOut) external returns (uint256 out);

    /// @notice The price of one LP token in the pool's invariant units (WAD, 1e18 == 1.0). Monotonically
    ///         non-decreasing as the pool earns fees, so `lp * virtualPrice / 1e18` lower-bounds the
    ///         redeemable single-coin value (a safe NAV for an over-collateralized stable pool).
    /// @dev **Read-only-reentrancy hazard:** this can be manipulated mid-callback on real pools. Never
    ///      call it during the adapter's own external interaction. See the adapter NatSpec.
    function get_virtual_price() external view returns (uint256);

    /// @notice Returns the token address at coin index `i`.
    function coins(uint256 i) external view returns (address);

    /// @notice Estimates LP minted (deposit==true) or burned (deposit==false) for `amounts`.
    /// @dev Used to size the slippage floor for `add_liquidity` / single-coin withdrawals. Does not
    ///      account for fees on most pools, so callers apply an extra `slippageBps` haircut.
    function calc_token_amount(uint256[2] calldata amounts, bool deposit) external view returns (uint256);

    /// @notice Estimates the single-coin output of burning `lp` LP for coin `i`.
    /// @dev Used to size the `minOut` slippage floor on withdrawals.
    function calc_withdraw_one_coin(uint256 lp, int128 i) external view returns (uint256);
}
