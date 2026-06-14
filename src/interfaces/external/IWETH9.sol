// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IERC20} from "@lattice/interfaces/IERC20.sol";

/// @title IWETH9
/// @author Modified from the canonical WETH9 (https://github.com/gnosis/canonical-weth/blob/master/contracts/WETH9.sol)
/// @notice Minimal vendored subset of Wrapped Ether (WETH9). The Lido adapter holds idle funds as
///         WETH (so the position fits the ERC-20 `IStrategy` ABI) and unwraps to native ETH only to
///         stake into Lido, re-wrapping the ETH it claims back from the withdrawal queue.
/// @dev Extends `IERC20` for `transfer`/`balanceOf`/`approve` plus the two wrap/unwrap selectors.
///      `withdraw(uint256)` sends native ETH to the caller (the adapter therefore needs a payable
///      `receive()`); `deposit()` wraps the attached ETH 1:1.
interface IWETH9 is IERC20 {
    /// @notice Wraps the attached native ETH 1:1, crediting the caller `msg.value` WETH.
    function deposit() external payable;

    /// @notice Burns `amount` WETH from the caller and returns `amount` native ETH to the caller.
    /// @param amount The amount of WETH to unwrap into native ETH.
    function withdraw(uint256 amount) external;
}
