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
///         the position's `(amount0, amount1)` are derived at that price, with token1 valued back
///         into token0. See `UniswapV3AdapterLib.totalAssetsManaged`.
///
///         **Swap-free.** The adapter never swaps. The keeper supplies BOTH token0 and token1 to the
///         adapter before `deploy`; the adapter only adds/removes liquidity. Accrued fees (token0 +
///         token1) and any leftover token1 from a withdraw are routed RAW to `rewardRecipient`.
///
///         **Two-token withdraw caveat.** `IStrategy.withdraw(amount, to)` is denominated in token0.
///         The adapter removes enough liquidity to free ~`amount` of token0-equivalent (sized via the
///         TWAP price), then sends the freed **token0** to `to` and routes the freed **token1** to
///         `to` as well. It is **shortfall-honest**: it returns the REAL token0 delta and never
///         over-reports. A single decreaseLiquidity frees token0 and token1 in the pool's current
///         ratio, so the token0 actually freed can be less than `amount`; the StrategyManager's
///         upstream shortfall check absorbs the remainder.
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
