// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAToken
/// @author Modified from Aave v3 (https://github.com/aave/aave-v3-core/blob/master/contracts/interfaces/IAToken.sol)
/// @notice Minimal vendored subset of the interest-bearing aToken.
/// @dev `balanceOf` is rebasing and equals the supplied underlying 1:1 (principal + accrued
///      interest), which is exactly the supply-leg valuation the adapter reports.
interface IAToken {
    /// @notice Returns the aToken balance (underlying-denominated, 1:1, includes accrued interest).
    function balanceOf(address user) external view returns (uint256);

    /// @notice Returns the scaled balance (principal in ray terms, excludes pending interest).
    function scaledBalanceOf(address user) external view returns (uint256);

    /// @notice Returns the address of the underlying asset backing this aToken.
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
