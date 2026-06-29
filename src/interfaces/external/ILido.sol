// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";

/// @title ILido
/// @author Modified from Lido stETH (https://github.com/lidofinance/lido-dao/blob/master/contracts/0.4.24/Lido.sol)
/// @notice Minimal vendored subset of the Lido `stETH` token. `submit` stakes native ETH and mints
///         the caller stETH (a rebasing share token valued 1:1 with ETH by Lido's own accounting).
/// @dev Extends `IERC20` for `balanceOf`/`approve`/`transfer`. NOTE: stETH is a *rebasing* balance;
///      the Lido adapter immediately wraps received stETH into the non-rebasing wstETH so its NAV
///      tracks yield through the wstETH→stETH exchange rate rather than a moving balance.
interface ILido is IERC20 {
    /// @notice Stakes the attached native ETH and mints stETH to the caller 1:1 with ETH submitted.
    /// @param referral Optional referral address for Lido's referral program (the adapter passes
    ///        `address(0)`).
    /// @return shares The amount of stETH shares minted for the submitted ETH.
    function submit(address referral) external payable returns (uint256 shares);
}
