// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IERC20} from "@lattice/interfaces/IERC20.sol";

/// @title IERC20Burnable
/// @notice Interface for burnable ERC-20 tokens.
interface IERC20Burnable is IERC20 {
    /// @notice Destroys `value` tokens from the caller's balance.
    function burn(uint256 value) external;

    /// @notice Destroys `value` tokens from `account`, deducting from the caller's allowance.
    function burnFrom(address account, uint256 value) external;
}
