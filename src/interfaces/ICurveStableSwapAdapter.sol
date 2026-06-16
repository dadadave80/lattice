// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ICurveStableSwapAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Curve-StableSwap-specific config ABI. The adapter also implements `IStrategy` +
///         `IProtocolAdapter`. Single-asset, single-sided LP adapter over a **2-coin** Curve
///         StableSwap pool: deposits the configured `asset` at `coinIndex`, holds (or stakes in a
///         gauge) the LP, and values the position via `get_virtual_price`. CRV/extra rewards are
///         forwarded RAW (swap-free) and are NOT counted in NAV.
interface ICurveStableSwapAdapter {
    /// @notice Emitted once at init with the wiring.
    /// @param pool       The Curve StableSwap pool.
    /// @param lpToken    The pool's LP token.
    /// @param asset      The underlying asset this adapter supplies/withdraws.
    /// @param coinIndex  The pool coin index `asset` occupies.
    event CurveStableSwapAdapterConfigured(
        address indexed pool, address indexed lpToken, address indexed asset, int128 coinIndex
    );

    /// @notice Emitted when the gauge is set or changed (address(0) == unstaked).
    event CurveGaugeSet(address indexed gauge);

    /// @notice Emitted when the slippage tolerance (bps) is changed.
    event CurveSlippageSet(uint256 slippageBps);

    /// @dev The reward recipient is announced via `IProtocolAdapter.RewardRecipientSet` (shared with
    ///      the generic adapter ABI) — not redeclared here to avoid an event-name collision when the
    ///      facet inherits both interfaces.

    /// @notice The pool's coin at the configured index does not match the configured asset.
    error CurveStableSwapAdapterAssetMismatch(address poolCoin, address configured);

    /// @notice The supplied coin index is out of range for a 2-coin pool (must be 0 or 1).
    error CurveStableSwapAdapterBadCoinIndex(int128 coinIndex);

    /// @notice The supplied slippage tolerance exceeds the allowed maximum (bps).
    error CurveStableSwapAdapterSlippageTooHigh(uint256 slippageBps, uint256 maxBps);

    /// @notice Returns the Curve StableSwap pool this adapter supplies to.
    function pool() external view returns (address);

    /// @notice Returns the pool's LP token.
    function lpToken() external view returns (address);

    /// @notice Returns the staking gauge (address(0) when the adapter holds LP unstaked).
    function gauge() external view returns (address);

    /// @notice Returns the CRV (primary gauge reward) token forwarded raw on harvest (address(0) == none).
    function crvToken() external view returns (address);

    /// @notice Returns the Lattice vault funds are returned to.
    function vault() external view returns (address);

    /// @notice Returns the pool coin index the adapter's asset occupies.
    function coinIndex() external view returns (int128);

    /// @notice Returns the configured slippage tolerance in basis points.
    function slippageBps() external view returns (uint256);

    /// @notice Sets the staking gauge (admin only). address(0) clears it (run unstaked). Setting a new
    ///         gauge does not migrate existing LP; stake/unstake happens on the next deploy/withdraw.
    function setGauge(address gauge) external;

    /// @notice Sets the CRV reward token forwarded raw on harvest (admin only). address(0) skips
    ///         forwarding (claim only). Decoupled from the gauge so integrators can wire the
    ///         deployment's canonical CRV address (or clear it) without re-deploying the facet.
    function setCrvToken(address token) external;

    /// @notice Sets the slippage tolerance in basis points (admin only).
    function setSlippageBps(uint256 slippageBps) external;

    /// @notice Sets the reward recipient (admin only).
    function setRewardRecipient(address recipient) external;
}
