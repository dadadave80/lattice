// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IERC4626} from "@lattice/interfaces/IERC4626.sol";

/// @title IVaultCore
/// @notice Interface for the VaultCore Diamond facet, extending ERC-4626 with strategy hooks.
/// @dev The vault tracks "idle" assets (held in this contract) vs "allocated" assets
///      (held by registered external strategies managed by the StrategyManager).
interface IVaultCore is IERC4626 {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  EVENTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Emitted when the strategy manager address is updated.
    event StrategyManagerSet(address indexed manager);

    /// @dev Emitted when assets are pushed from the vault to a strategy.
    event AssetsAllocated(address indexed strategy, uint256 amount);

    /// @dev Emitted when a strategy recall is acknowledged (assets return via separate transfer).
    event AssetsRecalled(address indexed strategy, uint256 amount);

    /// @dev Emitted when yield is harvested and totalAssets is updated.
    event YieldHarvested(uint256 totalAssetsAfter);

    //*//////////////////////////////////////////////////////////////////////////
    //                                  ERRORS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Reverts when a caller other than the configured strategy manager calls a manager-only function.
    error VaultCoreUnauthorizedManager(address caller);

    /// @dev Reverts when attempting to set an invalid manager address (e.g., address(0)).
    error VaultCoreInvalidManager();

    //*//////////////////////////////////////////////////////////////////////////
    //                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the address of the configured strategy manager, or address(0) if none.
    function strategyManager() external view returns (address);

    /// @notice Returns the vault's current idle asset balance (ERC-20 balance of this contract).
    function idleAssets() external view returns (uint256);

    /// @notice Returns the total assets allocated to strategies (totalAssets() - idleAssets()).
    /// @dev Will be 0 when no strategy manager is set.
    function allocatedAssets() external view returns (uint256);

    //*//////////////////////////////////////////////////////////////////////////
    //                          STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets the strategy manager address. Admin-only (DEFAULT_ADMIN_ROLE).
    /// @param manager The new strategy manager address.
    function setStrategyManager(address manager) external;

    /// @notice Transfers `amount` of the vault's idle assets to `strategy`.
    /// @dev Only callable by the configured strategy manager.
    /// @param strategy Destination strategy address.
    /// @param amount Amount of underlying asset to transfer.
    function allocateToStrategy(address strategy, uint256 amount) external;

    /// @notice Acknowledges a recall from `strategy`. The strategy itself transfers assets back.
    /// @dev Only callable by the configured strategy manager.
    /// @param strategy Source strategy address.
    /// @param amount Amount expected to be returned by the strategy.
    function recallFromStrategy(address strategy, uint256 amount) external;
}
