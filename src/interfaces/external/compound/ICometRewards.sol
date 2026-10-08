// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ICometRewards
/// @author ABI-equivalent interface authored fresh from Compound v3's public ABI
///         (https://github.com/compound-finance/comet/blob/main/contracts/CometRewards.sol).
///         Upstream license: BUSL-1.1 (not copied). Only the selectors the adapter calls are declared.
/// @notice Minimal ABI-equivalent interface: claim COMP rewards accrued in a Comet market.
interface ICometRewards {
    /// @notice Claims all accrued rewards for `src` in `comet`, sending them to `to`.
    function claimTo(address comet, address src, address to, bool shouldAccrue) external;

    /// @notice The reward token configured for a comet (used to forward raw).
    function rewardConfig(address comet) external view returns (address token, uint64 rescaleFactor, bool shouldUpscale);
}
