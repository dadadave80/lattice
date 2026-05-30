// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {VaultCoreLib} from "@lattice/defi/libraries/VaultCoreLib.sol";
import {IERC4626} from "@lattice/interfaces/IERC4626.sol";
import {IVaultCore} from "@lattice/interfaces/IVaultCore.sol";
import {ERC4626} from "@lattice/tokens/ERC4626.sol";

/// @title VaultCore
/// @notice Diamond facet extending ERC-4626 with strategy hooks for yield aggregation.
/// @dev All logic lives in VaultCoreLib. This contract is a pure delegator.
///
///      Initialization order in the consumer's Diamond initializer:
///        1. AccessControlLib.__AccessControl_init(admin)
///        2. ERC20Lib.__ERC20_init(name, symbol)
///        3. ERC4626Lib.__ERC4626_init(asset, decimalsOffset)
///        4. VaultCoreLib.__VaultCore_init()
///
///      `totalAssets()` is overridden to include assets held by registered strategies
///      so that ERC-4626 share pricing reflects the full vault balance.
contract VaultCore is ERC4626, IVaultCore {
    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-4626 OVERRIDE
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IERC4626
    /// @dev Overrides ERC4626.totalAssets() to include strategy allocations.
    function totalAssets() public view virtual override(ERC4626, IERC4626) returns (uint256) {
        return VaultCoreLib.totalAssets();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IVaultCore
    function strategyManager() external view virtual override returns (address) {
        return VaultCoreLib.strategyManager();
    }

    /// @inheritdoc IVaultCore
    function idleAssets() external view virtual override returns (uint256) {
        return VaultCoreLib.idleAssets();
    }

    /// @inheritdoc IVaultCore
    function allocatedAssets() external view virtual override returns (uint256) {
        return VaultCoreLib.allocatedAssets();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IVaultCore
    function setStrategyManager(address manager) external virtual override {
        VaultCoreLib.setStrategyManager(manager);
    }

    /// @inheritdoc IVaultCore
    function allocateToStrategy(address strategy, uint256 amount) external virtual override {
        VaultCoreLib.allocateToStrategy(strategy, amount);
    }

    /// @inheritdoc IVaultCore
    function recallFromStrategy(address strategy, uint256 amount) external virtual override {
        VaultCoreLib.recallFromStrategy(strategy, amount);
    }
}
