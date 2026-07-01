// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IERC3156FlashLender} from "@lattice/interfaces/external/IERC3156FlashLender.sol";

/// @title IERC20FlashMint
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20FlashMint.sol)
/// @notice Interface for the ERC-20 ERC-3156 flash-mint extension: the token itself is the flash lender.
/// @dev Adds no functions over {IERC3156FlashLender}; declares the revert reasons for ABI/decoding.
interface IERC20FlashMint is IERC3156FlashLender {
    /// @notice The loan token is not valid (only `address(this)` is supported).
    error ERC3156UnsupportedToken(address token);

    /// @notice The requested loan exceeds the max loan value for `token`.
    error ERC3156ExceededMaxLoan(uint256 maxLoan);

    /// @notice The receiver of a flash loan is not a valid {IERC3156FlashBorrower-onFlashLoan} implementer.
    error ERC3156InvalidReceiver(address receiver);
}
