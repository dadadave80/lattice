// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IStrategy
/// @author Modified from Yearn V3 (https://github.com/yearn/tokenized-strategy/blob/master/src/interfaces/ITokenizedStrategy.sol)
/// @notice Minimal interface for an external yield strategy managed by a StrategyManager.
/// @dev Strategies are trusted external contracts that accept asset deposits and report
///      their current managed balance. The vault PUSHES assets to a strategy via a direct
///      ERC-20 transfer; the strategy PULLS assets back to the vault via `withdraw`.
interface IStrategy {
    /// @notice Returns the address of the underlying asset this strategy manages.
    function asset() external view returns (address);

    /// @notice Returns the current total asset balance managed by this strategy.
    /// @dev This value is trusted by the StrategyManager and VaultCore for accounting.
    ///      Strategy implementations MUST report accurate balances to avoid mispricing vault shares.
    function totalAssetsManaged() external view returns (uint256);

    /// @notice Withdraws `amount` of the underlying asset to `to`.
    /// @dev Called by the StrategyManager during rebalancing to recall excess allocations.
    ///      The strategy is responsible for executing the ERC-20 transfer.
    /// @param amount Amount of underlying asset to withdraw.
    /// @param to Recipient address (typically the vault).
    /// @return withdrawn Actual amount transferred (may be less if strategy has slippage).
    function withdraw(uint256 amount, address to) external returns (uint256 withdrawn);
}
