// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {VaultCoreLib} from "@lattice/defi/libraries/VaultCoreLib.sol";
import {ERC4626Lib} from "@lattice/tokens/ERC4626/libraries/ERC4626Lib.sol";

/// @title VaultCore
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol)
/// @notice Diamond facet extending ERC-4626 with strategy hooks for yield aggregation.
/// @dev All logic lives in VaultCoreLib / ERC4626Lib. This contract is a pure delegator. It owns ONLY its own
///      selectors — the strategy surface (`strategyManager`/`idleAssets`/`allocatedAssets`/`setStrategyManager`/
///      `allocateToStrategy`/`recallFromStrategy`) plus the mutators it REPLACES on the base {ERC4626}
///      (`totalAssets` to include strategy allocations, and `deposit`/`mint`/`withdraw`/`redeem` behind the
///      read-only-reentrancy guard, delegating the vault math to {ERC4626Lib} directly). It does NOT inherit the
///      {ERC4626} facet — doing so would re-export the ERC-4626 + ERC-20 surfaces and collide with those
///      standalone facets in a Diamond; {DeployVaultCore} composes {ERC20} + {ERC4626} + {VaultCore} over one
///      shared storage layout.
///
///      Initialization order in the consumer's Diamond initializer:
///        1. AccessControlLib.__AccessControl_init(admin)
///        2. ERC20Lib.__ERC20_init(name, symbol)
///        3. ERC4626Lib.__ERC4626_init(asset, decimalsOffset)
///        4. VaultCoreLib.__VaultCore_init()
///
///      `totalAssets()` is overridden to include assets held by registered strategies
///      so that ERC-4626 share pricing reflects the full vault balance.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract VaultCore {
    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-4626 OVERRIDE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns total assets including strategy allocations.
    /// @dev Replaces the base {ERC4626} `totalAssets()` to include assets held by registered strategies.
    function totalAssets() public view virtual returns (uint256) {
        return VaultCoreLib.totalAssets();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the strategy manager authorized to allocate/recall vault assets.
    function strategyManager() external view virtual returns (address) {
        return VaultCoreLib.strategyManager();
    }

    /// @notice Returns assets held idle in the vault (not allocated to any strategy).
    function idleAssets() external view virtual returns (uint256) {
        return VaultCoreLib.idleAssets();
    }

    /// @notice Returns assets currently allocated to registered strategies.
    function allocatedAssets() external view virtual returns (uint256) {
        return VaultCoreLib.allocatedAssets();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets the strategy manager address (admin-gated).
    function setStrategyManager(address manager) external virtual {
        VaultCoreLib.setStrategyManager(manager);
    }

    /// @notice Pushes `amount` of idle assets to `strategy` (strategy-manager-gated).
    function allocateToStrategy(address strategy, uint256 amount) external virtual {
        VaultCoreLib.allocateToStrategy(strategy, amount);
    }

    /// @notice Recalls `amount` of assets from `strategy` back to the vault (strategy-manager-gated).
    function recallFromStrategy(address strategy, uint256 amount) external virtual {
        VaultCoreLib.recallFromStrategy(strategy, amount);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    ERC-4626 ENTRY GUARDS (READ-ONLY REENTRANCY)
    //////////////////////////////////////////////////////////////////////////*//
    // Share-price-sensitive entry points are rejected while the strategy manager is mid-rebalance,
    // when totalAssets() (idle + strategy-reported) is transiently inconsistent. This closes the
    // read-only-reentrancy window where a strategy callback re-enters the vault during rebalance().
    // These REPLACE the base {ERC4626} mutators, delegating the vault math to {ERC4626Lib} directly.

    /// @notice Deposits `assets` for shares to `receiver` (rejected mid-rebalance).
    function deposit(uint256 assets, address receiver) public virtual returns (uint256) {
        VaultCoreLib.requireManagerNotRebalancing();
        return ERC4626Lib.deposit(assets, receiver);
    }

    /// @notice Mints exactly `shares` to `receiver` (rejected mid-rebalance).
    function mint(uint256 shares, address receiver) public virtual returns (uint256) {
        VaultCoreLib.requireManagerNotRebalancing();
        return ERC4626Lib.mint(shares, receiver);
    }

    /// @notice Withdraws exactly `assets` to `receiver`, burning `owner`'s shares (rejected mid-rebalance).
    function withdraw(uint256 assets, address receiver, address owner) public virtual returns (uint256) {
        VaultCoreLib.requireManagerNotRebalancing();
        return ERC4626Lib.withdraw(assets, receiver, owner);
    }

    /// @notice Redeems exactly `shares` from `owner` to `receiver` (rejected mid-rebalance).
    function redeem(uint256 shares, address receiver, address owner) public virtual returns (uint256) {
        VaultCoreLib.requireManagerNotRebalancing();
        return ERC4626Lib.redeem(shares, receiver, owner);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect VaultCore methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `allocateToStrategy(address,uint256)` 0x5915e15d
    ///      `allocatedAssets()` 0x36cd2b11
    ///      `deposit(uint256,address)` 0x6e553f65
    ///      `idleAssets()` 0xe16b03a3
    ///      `mint(uint256,address)` 0x94bf804d
    ///      `recallFromStrategy(address,uint256)` 0x43ff28f3
    ///      `redeem(uint256,address,address)` 0xba087652
    ///      `setStrategyManager(address)` 0x5c966646
    ///      `strategyManager()` 0x39b70e38
    ///      `totalAssets()` 0x01e1d114
    ///      `withdraw(uint256,address,address)` 0xb460af94
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"5915e15d36cd2b116e553f65e16b03a394bf804d43ff28f3ba0876525c96664639b70e3801e1d114b460af94";
    }
}
