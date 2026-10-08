// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IUniswapV3Adapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Uniswap V3 (https://github.com/Uniswap/v3-periphery)
/// @notice Uniswap-V3-specific config ABI. The adapter also implements `IStrategy` +
///         `IProtocolAdapter`. A **CUSTOM** adapter: a Uniswap V3 LP is a two-token, NFT-wrapped
///         concentrated-liquidity position, which does not map cleanly onto the single-asset
///         `IStrategy` surface. The adapter pins the position to **full-range** (min/max usable
///         ticks) so there is no active range management, and the adapter's `asset` is **token0**
///         (the vault-facing accounting token).
///
///         **Valuation (the central risk).** NAV is computed from the pool's **TWAP**
///         (`pool.observe` over `twapWindow`), NEVER from `slot0` spot — the spot tick is
///         single-block manipulable, so reading it for share pricing would let an attacker mint/burn
///         vault shares at a flash-loan-skewed price. The TWAP tick is converted to a sqrt price and
///         the position's token0 leg is derived at that price.
///
///         **NAV is token0 only.** The vault can only ever receive token0, so NAV is idle token0 plus
///         the position's token0 leg. token1 is never counted, whether idle in the adapter or in the
///         position's token1 leg, so NAV never includes value a redeemer cannot receive. See
///         `UniswapV3AdapterLib.totalAssetsManaged`.
///
///         **Swap-free.** The adapter never swaps. The keeper supplies BOTH token0 and token1 to the
///         adapter before `deploy`; the adapter only adds/removes liquidity. The keeper's token1 never
///         enters NAV. Accrued fees (token0 + token1) are routed RAW to `rewardRecipient` on `harvest`;
///         idle balances never are.
///
///         **Deploy bound.** The pool prices a mint at spot while NAV counts the new token0 leg at the
///         TWAP, so a deploy steps NAV by about `consumed0 × (√(P_spot / P_twap) − 1)`: flat only at
///         spot == TWAP. `deploy` runs inside the permissionless `rebalance()`, so it refuses a step larger
///         than `slippageBps` of the token0 consumed (`UniswapV3AdapterDeployOffTwap`). Within that bound
///         an attacker who moves spot can still choose the step.
///
///         **Withdraw pays idle token0 only.** `IStrategy.withdraw(amount, to)` is denominated in
///         token0 and sends only the adapter's idle token0; it never removes liquidity (a decrease pays
///         out at spot against the TWAP-counted leg, which the StrategyManager's value-loss check would
///         reject whenever spot sits above the TWAP). It is **shortfall-honest**: it returns the REAL
///         token0 delta and never over-reports; the StrategyManager accepts the partial recall.
///
///         **Exit.** `rebalance()` can allocate into the position but never recall from it, so capital
///         allocated here reaches redeemers only after the admin's `emergencyWithdraw`. At a target of 0
///         a rebalance recalls the idle token0, the token0 leg stays counted, and `removeStrategy`
///         refuses. The admin's `emergencyWithdraw` removes the position and sends both tokens to the
///         vault, and the strategy can then be removed. The token0 replaces the counted leg but is paid at
///         spot with no floor, so NAV steps by about `leg0 × (√(P_twap / P_spot) − 1)`: exit while spot
///         sits near the TWAP. The token1 lands in the vault outside NAV; VaultCore has no sweep for a
///         non-asset token.
interface IUniswapV3Adapter {
    /// @notice Emitted once at init with the core wiring.
    /// @param positionManager The Uniswap V3 NonfungiblePositionManager.
    /// @param pool   The Uniswap V3 pool the position LPs into.
    /// @param token0 The pool's token0 (== the adapter's asset).
    /// @param token1 The pool's token1.
    /// @param fee    The pool fee tier.
    event UniswapV3AdapterConfigured(
        address indexed positionManager, address indexed pool, address token0, address indexed token1, uint24 fee
    );

    /// @notice Emitted when the full-range position NFT is first minted.
    /// @param tokenId   The minted position id.
    /// @param liquidity The initial liquidity added.
    event UniswapV3PositionMinted(uint256 indexed tokenId, uint128 liquidity);

    /// @notice Emitted when the TWAP observation window is changed.
    event UniswapV3TwapWindowSet(uint32 twapWindow);

    /// @notice Emitted when the slippage tolerance (bps) is changed.
    event UniswapV3SlippageSet(uint256 slippageBps);

    /// @dev The reward recipient is announced via `IProtocolAdapter.RewardRecipientSet` (shared with
    ///      the generic adapter ABI) — not redeclared here to avoid an event-name collision when the
    ///      facet inherits both interfaces.

    /// @notice The pool's token0/token1/fee do not match the configured values.
    error UniswapV3AdapterPoolMismatch();

    /// @notice The supplied slippage tolerance exceeds the allowed maximum (bps).
    error UniswapV3AdapterSlippageTooHigh(uint256 slippageBps, uint256 maxBps);

    /// @notice The supplied TWAP window is zero (an instantaneous "TWAP" is just spot — disallowed).
    error UniswapV3AdapterTwapWindowZero();

    /// @notice The pool reported a non-positive tick spacing (cannot align a full-range position).
    error UniswapV3AdapterBadTickSpacing(int24 tickSpacing);

    /// @notice The position manager's `positions()` call failed or returned short data.
    /// @param tokenId The adapter's position NFT id.
    error UniswapV3AdapterPositionsCallFailed(uint256 tokenId);

    /// @notice A deploy consumed `consumed0` token0 at the pool's spot price, but the liquidity it added holds
    ///         `counted0` token0 at the TWAP, and the gap exceeds `slippageBps` of `consumed0`. Spot is too far
    ///         from the TWAP: deploying would step the vault's NAV by that gap.
    /// @param consumed0 The token0 the mint or increase took from the adapter.
    /// @param counted0 The token0 the added liquidity holds at the TWAP price, as NAV counts it.
    error UniswapV3AdapterDeployOffTwap(uint256 consumed0, uint256 counted0);

    /// @notice Returns the Uniswap V3 NonfungiblePositionManager.
    function positionManager() external view returns (address);

    /// @notice Returns the Uniswap V3 pool the adapter LPs into.
    function pool() external view returns (address);

    /// @notice Returns the pool's token0 (== the adapter's asset, the vault-facing accounting token).
    function token0() external view returns (address);

    /// @notice Returns the pool's token1 (supplied by the keeper, never swapped by the adapter).
    function token1() external view returns (address);

    /// @notice Returns the pool fee tier (hundredths of a bip).
    function fee() external view returns (uint24);

    /// @notice Returns the current position NFT id (0 == no position minted yet).
    function tokenId() external view returns (uint256);

    /// @notice Returns the Lattice vault funds are returned to on emergency exit.
    function vault() external view returns (address);

    /// @notice Returns the TWAP observation window (seconds) used for valuation.
    function twapWindow() external view returns (uint32);

    /// @notice Returns the configured slippage tolerance in basis points.
    function slippageBps() external view returns (uint256);

    /// @notice Sets the TWAP observation window in seconds (admin only). Must be non-zero.
    function setTwapWindow(uint32 twapWindow) external;

    /// @notice Sets the slippage tolerance in basis points (admin only).
    function setSlippageBps(uint256 slippageBps) external;

    /// @notice Sets the reward recipient (admin only).
    function setRewardRecipient(address recipient) external;
}
