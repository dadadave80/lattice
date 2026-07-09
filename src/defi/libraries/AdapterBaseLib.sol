// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";

/// @title AdapterBaseLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol)
/// @notice Shared, security-critical primitives reused by every Lattice protocol adapter:
///         exact-amount `forceApprove` (USDT/no-return safe), raw reward forwarding that
///         reports the real received delta (fee-on-transfer safe), and shortfall-honest
///         transfers. Stateless utility library — no own ERC-7201 slot, no facet, no
///         interface file. Errors are declared here.
/// @dev Operates on `address(this)` of the *calling* adapter (these are `internal` and run in
///      the adapter's context). External-protocol targets must be freshly resolved by the
///      caller before invoking `forceApprove` (re-resolve PoolAddressesProvider each call).
library AdapterBaseLib {
    /// @notice A low-level ERC-20 op (transfer/approve) failed.
    error AdapterSafeERC20FailedOperation(address token);

    /// @notice Returns the calling adapter's balance of `token`.
    function balanceOfSelf(address token) internal view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Sets `spender`'s allowance over the adapter's `token` to exactly `amount`.
    /// @dev Resets to 0 first to support tokens (USDT) that revert on non-zero→non-zero
    ///      approvals; tolerates tokens that return no data. Never grants an infinite
    ///      allowance. Callers pass the freshly-resolved protocol target as `spender`.
    function forceApprove(address token, address spender, uint256 amount) internal {
        // Reset to zero (ignore failure: some tokens revert if allowance already 0).
        (bool ok0, bytes memory ret0) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, uint256(0)));
        // Only treat an explicit `false` return as a hard failure of the reset.
        if (ok0 && ret0.length > 0 && !abi.decode(ret0, (bool))) {
            revert AdapterSafeERC20FailedOperation(token);
        }
        // Set the exact amount.
        (bool ok1, bytes memory ret1) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        if (!ok1 || (ret1.length > 0 && !abi.decode(ret1, (bool)))) {
            revert AdapterSafeERC20FailedOperation(token);
        }
    }

    /// @notice Transfers the adapter's entire `rewardToken` balance to `recipient` and returns
    ///         the *real* amount the recipient received (measured by balance delta).
    /// @dev Zero balance is a no-op returning 0 (so a stuck/zero-claim reward never reverts the
    ///      caller). Fee-on-transfer is handled by measuring the recipient's delta. Reverts
    ///      `AdapterSafeERC20FailedOperation` only on an explicit transfer failure.
    function forwardRewardRaw(address rewardToken, address recipient) internal returns (uint256 forwarded) {
        uint256 bal = IERC20(rewardToken).balanceOf(address(this));
        if (bal == 0) return 0;
        uint256 beforeBal = IERC20(rewardToken).balanceOf(recipient);
        (bool ok, bytes memory ret) = rewardToken.call(abi.encodeWithSelector(IERC20.transfer.selector, recipient, bal));
        if (!ok || (ret.length > 0 && !abi.decode(ret, (bool)))) {
            revert AdapterSafeERC20FailedOperation(rewardToken);
        }
        forwarded = IERC20(rewardToken).balanceOf(recipient) - beforeBal;
    }

    /// @notice Transfers up to `amount` of `token` to `to`, capped at the adapter's balance,
    ///         and returns the real amount transferred.
    /// @dev Shortfall-honest: when the adapter holds less than requested (e.g. after a partial
    ///      liquidation), it sends what it has and reports that. The StrategyManager turns an
    ///      under-delivery into `StrategyManagerWithdrawShortfall` upstream.
    function transferHonest(address token, address to, uint256 amount) internal returns (uint256 sent) {
        uint256 bal = IERC20(token).balanceOf(address(this));
        sent = amount > bal ? bal : amount;
        if (sent == 0) return 0;
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, sent));
        if (!ok || (ret.length > 0 && !abi.decode(ret, (bool)))) {
            revert AdapterSafeERC20FailedOperation(token);
        }
    }
}
