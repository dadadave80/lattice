// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAaveRewardsController
/// @author Modified from Aave v3 periphery (https://github.com/aave/aave-v3-periphery/blob/master/contracts/rewards/interfaces/IRewardsController.sol)
/// @notice Minimal vendored subset: claim all incentive rewards accrued to an account for a set
///         of assets (aTokens / debt tokens).
interface IAaveRewardsController {
    /// @notice Claims all pending rewards for `assets`, sending each reward token to `to`.
    /// @param assets       The (a/debt)Token addresses to claim rewards for.
    /// @param to           Recipient of the claimed reward tokens (the adapter).
    /// @return rewardsList The reward token addresses claimed.
    /// @return claimedAmounts The amount claimed per reward token (same order as rewardsList).
    function claimAllRewards(address[] calldata assets, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
}
