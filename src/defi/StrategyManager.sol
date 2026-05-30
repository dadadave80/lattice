// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StrategyManagerLib} from "@lattice/defi/libraries/StrategyManagerLib.sol";
import {IStrategyManager} from "@lattice/interfaces/IStrategyManager.sol";

/// @title StrategyManager
/// @notice Diamond facet managing yield strategy allocations for a single ERC-4626 vault.
/// @dev All logic lives in StrategyManagerLib. This contract is a pure delegator.
///
///      Initialization order in the consumer's Diamond initializer:
///        1. AccessControlLib.__AccessControl_init(admin)
///        2. StrategyManagerLib.__StrategyManager_init()
///        3. (Optional) StrategyManagerLib._setVault(vault)
///
///      The StrategyManager must be configured as the vault's strategy manager via
///      `IVaultCore.setStrategyManager(address(this))` before calling `rebalance()`.
///      `allocateToStrategy` is guarded by `_checkManager()` which checks the caller
///      address, not any role — granting DEFAULT_ADMIN_ROLE is neither necessary nor sufficient.
contract StrategyManager is IStrategyManager {
    //*//////////////////////////////////////////////////////////////////////////
    //                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IStrategyManager
    function vault() external view virtual override returns (address) {
        return StrategyManagerLib.vault();
    }

    /// @inheritdoc IStrategyManager
    function getStrategies() external view virtual override returns (address[] memory) {
        return StrategyManagerLib.getStrategies();
    }

    /// @inheritdoc IStrategyManager
    function getStrategyTarget(address strategy) external view virtual override returns (uint16 targetBps) {
        return StrategyManagerLib.getStrategyTarget(strategy);
    }

    /// @inheritdoc IStrategyManager
    function totalAllocated() external view virtual override returns (uint256) {
        return StrategyManagerLib.totalAllocated();
    }

    /// @inheritdoc IStrategyManager
    function totalTargetBps() external view virtual override returns (uint256) {
        return StrategyManagerLib.totalTargetBps();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IStrategyManager
    function setVault(address _vault) external virtual override {
        StrategyManagerLib.setVault(_vault);
    }

    /// @inheritdoc IStrategyManager
    function addStrategy(address strategy, uint16 targetBps) external virtual override {
        StrategyManagerLib.addStrategy(strategy, targetBps);
    }

    /// @inheritdoc IStrategyManager
    function removeStrategy(address strategy) external virtual override {
        StrategyManagerLib.removeStrategy(strategy);
    }

    /// @inheritdoc IStrategyManager
    function updateStrategyTarget(address strategy, uint16 newBps) external virtual override {
        StrategyManagerLib.updateStrategyTarget(strategy, newBps);
    }

    /// @inheritdoc IStrategyManager
    function harvest() external virtual override {
        StrategyManagerLib.harvest();
    }

    /// @inheritdoc IStrategyManager
    function rebalance() external virtual override {
        StrategyManagerLib.rebalance();
    }
}
