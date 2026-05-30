// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IStrategyManager
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

    /// @dev Emitted when a strategy's target allocation (in bps) is updated.
    event StrategyTargetUpdated(address indexed strategy, uint16 oldBps, uint16 newBps);

    /// @dev Emitted after a harvest sweep of all strategies.
    event Harvested(uint256 totalAllocated);

    /// @dev Emitted after a rebalance operation completes.
    event Rebalanced();

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

    /// @dev Reverts when a strategy delivers fewer assets than requested during rebalance.
    /// @param strategy The strategy that underdelivered.
    /// @param requested The amount requested from the strategy.
    /// @param actual The amount the strategy actually transferred.
    error StrategyManagerWithdrawShortfall(address strategy, uint256 requested, uint256 actual);

    /// @dev Reverts when attempting to remove a strategy that still holds vault assets.
    ///      Use forceRemove (if provided) or recall assets first via rebalance().
    error StrategyManagerStrategyStillAllocated(address strategy, uint256 balance);

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
    /// @dev Trust assumption: strategies are trusted to report accurate balances.
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
    /// @param strategy Address of the strategy to register.
    /// @param targetBps Target allocation in basis points (0–10 000).
    function addStrategy(address strategy, uint16 targetBps) external;

    /// @notice Removes a registered strategy. Admin-only.
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
    /// @dev Pushes or recalls assets to/from strategies. Anyone can call.
    function rebalance() external;
}
