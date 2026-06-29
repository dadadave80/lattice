// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";

/// @title IERC20Capped
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Capped.sol)
/// @notice Interface for ERC-20 tokens with a capped total supply.
interface IERC20Capped is IERC20 {
    /// @dev Thrown when a mint would cause the total supply to exceed the cap.
    error ERC20ExceededCap(uint256 increasedSupply, uint256 cap);

    /// @dev Thrown when the cap is set to zero.
    error ERC20InvalidCap(uint256 cap);

    /// @notice Returns the cap on the token's total supply.
    function cap() external view returns (uint256);
}
