// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IComet
/// @author Modified from Compound v3 (https://github.com/compound-finance/comet/blob/main/contracts/CometMainInterface.sol)
/// @notice Minimal vendored subset of a Compound v3 Comet market (base-asset supply leg).
interface IComet {
    /// @notice Supplies `amount` of `asset` (the base asset) to the caller's position.
    function supply(address asset, uint256 amount) external;

    /// @notice Withdraws `amount` of `asset` (base asset) to the caller.
    function withdraw(address asset, uint256 amount) external;

    /// @notice Returns the caller's supplied base-asset balance (accrues interest, 1:1 base units).
    function balanceOf(address account) external view returns (uint256);

    /// @notice Returns the base token (the yield-bearing asset) of this market.
    function baseToken() external view returns (address);

    /// @notice Accrues interest/rewards state for `account` so reads are fresh.
    function accrueAccount(address account) external;
}
