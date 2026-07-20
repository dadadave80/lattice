// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ICurveGauge
/// @author Modified from Curve LiquidityGauge (https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/gauges/LiquidityGaugeV5.vy)
/// @notice Minimal vendored subset of a Curve liquidity gauge used to stake LP tokens for CRV (and
///         optional extra) rewards. Optional: the adapter runs unstaked (gauge == address(0)) or
///         stakes its LP here. Only the selectors the adapter calls are declared.
interface ICurveGauge {
    /// @notice Stakes `value` LP tokens (pulled from the caller; the adapter approves first).
    function deposit(uint256 value) external;

    /// @notice Unstakes `value` LP tokens back to the caller.
    function withdraw(uint256 value) external;

    /// @notice Claims all pending reward tokens (CRV + extras) for `addr`, sending them to `addr`.
    function claim_rewards(address addr) external;

    /// @notice Returns the caller's / `account`'s staked LP balance.
    function balanceOf(address account) external view returns (uint256);
}
