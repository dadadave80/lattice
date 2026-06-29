// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";

/// @title IWstETH
/// @author Modified from Lido wstETH (https://github.com/lidofinance/lido-dao/blob/master/contracts/0.6.12/WstETH.sol)
/// @notice Minimal vendored subset of Lido wrapped stETH (wstETH), a non-rebasing wrapper around the
///         rebasing stETH. The Lido adapter holds its staked position as wstETH so its share balance
///         is constant and yield accrues through the rising `getStETHByWstETH` exchange rate.
/// @dev Extends `IERC20` for `balanceOf`/`approve`/`transfer`. `wrap`/`unwrap` move between stETH and
///      wstETH (the adapter approves stETH to the wstETH contract before `wrap`). The two `get*`
///      views are the exchange-rate readers used to value the position in ETH/WETH units.
interface IWstETH is IERC20 {
    /// @notice Wraps `stETHAmount` of stETH (pulled from the caller) into wstETH minted to the caller.
    /// @param stETHAmount The amount of stETH to wrap.
    /// @return wstETHAmount The amount of wstETH minted to the caller.
    function wrap(uint256 stETHAmount) external returns (uint256 wstETHAmount);

    /// @notice Unwraps `wstETHAmount` of wstETH (burned from the caller) into stETH sent to the caller.
    /// @param wstETHAmount The amount of wstETH to unwrap.
    /// @return stETHAmount The amount of stETH returned to the caller.
    function unwrap(uint256 wstETHAmount) external returns (uint256 stETHAmount);

    /// @notice Returns the amount of stETH `wstETHAmount` of wstETH is currently worth (WAD-rate).
    /// @dev Monotonically non-decreasing as Lido accrues staking rewards, so the adapter values its
    ///      wstETH balance in stETH (== ETH ~1:1) units via this reader.
    function getStETHByWstETH(uint256 wstETHAmount) external view returns (uint256 stETHAmount);

    /// @notice Returns the amount of wstETH `stETHAmount` of stETH is currently worth.
    function getWstETHByStETH(uint256 stETHAmount) external view returns (uint256 wstETHAmount);
}
