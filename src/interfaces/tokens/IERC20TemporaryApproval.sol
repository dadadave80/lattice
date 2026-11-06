// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IERC20TemporaryApproval
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/token/ERC20/extensions/draft-ERC20TemporaryApproval.sol)
/// @notice ERC-7674 temporary allowances, additional to ordinary ERC-20 allowances.
interface IERC20TemporaryApproval {
    /// @notice Sets the caller's temporary allowance for `spender` to `value` for this transaction.
    /// @dev Overwrites the previous temporary grant. Does not change persistent approval or emit Approval.
    ///      `allowance` reports their saturated sum; spending consumes temporary allowance first.
    function temporaryApprove(address spender, uint256 value) external returns (bool);
}
