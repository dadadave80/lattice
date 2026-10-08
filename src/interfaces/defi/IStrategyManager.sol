// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IStrategyManager
/// @author Modified from Yearn V3 (https://github.com/yearn/yearn-vaults-v3/blob/master/contracts/VaultV3.vy)
/// @notice Interface for the StrategyManager Diamond facet.
/// @dev The StrategyManager maintains a list of registered yield strategies for a single vault,
///      tracks allocation targets (in basis points), and orchestrates rebalancing.
interface IStrategyManager {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  EVENTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Emitted when the associated vault address is set.
    event VaultSet(address indexed vault);

    /// @dev Emitted when a new strategy is registered with a target allocation.
    event StrategyAdded(address indexed strategy, uint16 targetBps);

    /// @dev Emitted when a strategy is removed from the registry.
    event StrategyRemoved(address indexed strategy);

    /// @dev Emitted (before {StrategyRemoved}) when `removeStrategy` drops a strategy whose
    ///      `totalAssetsManaged()` read fails. Any funds it still holds leave the vault's NAV; if they are
    ///      later returned to the vault, they accrue to whoever holds shares then, including depositors who
    ///      entered after the removal.
    event StrategyForceRemoved(address indexed strategy);

    /// @dev Emitted when a strategy's target allocation (in bps) is updated.
    event StrategyTargetUpdated(address indexed strategy, uint16 oldBps, uint16 newBps);

    /// @dev Emitted after a harvest sweep of all strategies.
    event Harvested(uint256 totalAllocated);

    /// @dev Emitted after a rebalance operation completes.
    event Rebalanced();

    /// @dev Emitted when `rebalance()` recalls less than it requested from a strategy that still reports the
    ///      undelivered part (an honest partial recall, e.g. a Lido buffer that is short, or an Aave or Compound
    ///      market whose cash is borrowed out). The strategy stays over its target until a later rebalance
    ///      recalls the rest.
    /// @param strategy The strategy recalled from.
    /// @param requested The amount requested.
    /// @param received The amount the vault actually received.
    event StrategyPartiallyRecalled(address indexed strategy, uint256 requested, uint256 received);

    /// @dev Emitted when `rebalance()` calls a protocol adapter's `deploy()` to put its idle to work and the
    ///      call reverts (e.g. the adapter or its protocol is paused). The idle stays in the adapter, still
    ///      counted in its NAV, and the rebalance completes.
    /// @param strategy The adapter whose deploy failed.
    /// @param reason The revert data.
    event StrategyDeployFailed(address indexed strategy, bytes reason);

    //*//////////////////////////////////////////////////////////////////////////
    //                                  ERRORS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Reverts when the vault has not been set and a vault-dependent operation is called.
    error StrategyManagerVaultNotSet();

    /// @dev Reverts when an invalid strategy address is provided (e.g., address(0)).
    error StrategyManagerInvalidStrategy(address strategy);

    /// @dev Reverts when attempting to add a strategy that is already registered.
    error StrategyManagerStrategyAlreadyAdded(address strategy);

    /// @dev Reverts when a strategy address is not found in the registry.
    error StrategyManagerStrategyNotFound(address strategy);

    /// @dev Reverts when adding/updating a strategy would push total allocation above 10 000 bps.
    error StrategyManagerInvalidAllocation(uint256 totalBps);

    /// @dev Reverts when a strategy's underlying asset does not match the vault's asset.
    error StrategyManagerAssetMismatch(address strategy);

    /// @dev Reverts when a rebalance recall loses value: the strategy's reported balance drops by more than the
    ///      vault actually received, beyond a fixed rounding tolerance (slippage, an exit fee, or a strategy
    ///      that writes off more than it pays). An honest partial recall does not revert.
    /// @param strategy The strategy that underdelivered.
    /// @param released The drop in the strategy's reported balance across the recall.
    /// @param received The amount the vault actually received.
    error StrategyManagerWithdrawShortfall(address strategy, uint256 released, uint256 received);

    /// @dev Reverts when attempting to remove a strategy that still holds vault assets.
    ///      Recall assets first via rebalance() (set the target to 0, then rebalance). Only a strategy whose
    ///      balance read fails is removed without this check (see {StrategyForceRemoved}).
    error StrategyManagerStrategyStillAllocated(address strategy, uint256 balance);

    /// @dev Reverts when adding a strategy that already reports a balance. A new strategy must start empty so
    ///      that adding it cannot step the vault's NAV up, e.g. re-adding a force-removed strategy that still
    ///      holds the stranded funds, which would hand them to whoever deposited after the removal.
    error StrategyManagerStrategyNotEmpty(address strategy, uint256 balance);

    /// @dev Reverts when adding a strategy would exceed the MAX_STRATEGIES cap.
    error StrategyManagerTooManyStrategies();

    //*//////////////////////////////////////////////////////////////////////////
    //                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the address of the associated vault.
    function vault() external view returns (address);

    /// @notice Returns the list of all registered strategy addresses.
    function getStrategies() external view returns (address[] memory);

    /// @notice Returns the target allocation in basis points for a given strategy.
    /// @param strategy Strategy address to query.
    /// @return targetBps Basis-point target (0–10 000); 0 if strategy is not registered.
    function getStrategyTarget(address strategy) external view returns (uint16 targetBps);

    /// @notice Returns the sum of `IStrategy.totalAssetsManaged()` across all registered strategies.
    /// @dev Trust assumption: strategies are trusted to report accurate balances. Reverts if any strategy's
    ///      read reverts or the sum overflows, which makes a VaultCore vault's `totalAssets()` revert (fail closed).
    function totalAllocated() external view returns (uint256);

    /// @notice Returns the current sum of all registered strategy target allocations in basis points.
    function totalTargetBps() external view returns (uint256);

    //*//////////////////////////////////////////////////////////////////////////
    //                          STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets the vault address. Admin-only (DEFAULT_ADMIN_ROLE).
    /// @param _vault Address of the ERC-4626 vault this manager serves.
    function setVault(address _vault) external;

    /// @notice Registers a new strategy with a target allocation. Admin-only.
    /// @dev Reverts with {StrategyManagerStrategyNotEmpty} if the strategy already reports a balance, and bubbles
    ///      the revert if its `totalAssetsManaged()` read fails.
    /// @param strategy Address of the strategy to register.
    /// @param targetBps Target allocation in basis points (0–10 000).
    function addStrategy(address strategy, uint16 targetBps) external;

    /// @notice Removes a registered strategy. Admin-only.
    /// @dev Reverts with {StrategyManagerStrategyStillAllocated} while the strategy reports a balance. A strategy
    ///      whose `totalAssetsManaged()` read fails is force-removed instead, emitting {StrategyForceRemoved};
    ///      any funds it still holds leave the vault's NAV and deposits reopen at the lower NAV. Returning
    ///      those funds later moves their value to whoever holds shares then, including post-removal
    ///      depositors, and the strategy cannot be re-added while it reports a balance.
    /// @param strategy Address of the strategy to remove.
    function removeStrategy(address strategy) external;

    /// @notice Updates the target allocation for a registered strategy. Admin-only.
    /// @param strategy Address of the registered strategy.
    /// @param newBps New target allocation in basis points.
    function updateStrategyTarget(address strategy, uint16 newBps) external;

    /// @notice Snapshots the current allocated balance across all strategies and emits Harvested.
    /// @dev Anyone can call; does not move funds. Useful for off-chain indexers.
    function harvest() external;

    /// @notice Rebalances the vault's asset distribution to match strategy target allocations.
    /// @dev Pushes or recalls assets to/from strategies, then calls `deploy()` on each strategy that advertises
    ///      `IProtocolAdapter` and holds idle asset. Anyone can call. A recall that loses value beyond a fixed
    ///      rounding tolerance reverts with {StrategyManagerWithdrawShortfall}; an honest partial recall emits
    ///      {StrategyPartiallyRecalled}; a failing deploy emits {StrategyDeployFailed}. Allocations are capped
    ///      at the vault's actual idle balance.
    function rebalance() external;
}
