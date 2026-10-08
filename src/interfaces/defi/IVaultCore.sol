// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";

/// @title IVaultCore
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol)
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

    /// @dev Reverts when a share-price-sensitive entry point (deposit/mint/withdraw/redeem) is
    ///      called while the configured strategy manager is mid-`rebalance()`. During a rebalance
    ///      the vault's idle balance and the strategies' reported balances are transiently
    ///      inconsistent, so `totalAssets()` (and therefore the share price) cannot be trusted.
    ///      Blocking these entries defeats read-only reentrancy via a strategy callback.
    error VaultCoreManagerRebalancing();

    /// @dev Reverts from `totalAssets()` when the configured strategy manager's `totalAllocated()` read fails
    ///      (e.g. a registered strategy's `totalAssetsManaged()` reverts). The vault's NAV is then unknown, so
    ///      share pricing fails closed: `totalAssets()`, the converters and the previews revert, the ERC-4626
    ///      `max*` views return 0 and every entry and exit reverts. Recovery: the manager admin force-removes a
    ///      strategy whose read reverts (see {IStrategyManager-removeStrategy}); if none can be removed (e.g. a
    ///      well-formed balance that overflows the sum), the vault admin calls `setStrategyManager` with a
    ///      fresh manager. Either way the affected strategies' funds leave the NAV, and returning them later
    ///      moves their value to whoever holds shares at that moment. A force removal therefore latches
    ///      deposits closed ({VaultCoreDepositsLatched}) until the manager admin clears the latch, so no new
    ///      depositor shares in returned funds; they accrue to whoever still holds shares when they return (a
    ///      holder who exits while latched is priced on the idle-only NAV). The `setStrategyManager` route sets
    ///      no latch: the fresh manager starts unlatched and deposits reopen at once, so funds the old
    ///      manager's strategies return later still move value to post-switch depositors.
    error VaultCoreStrategyNavUnavailable(address manager);

    /// @dev Reverts from `deposit`/`mint` while the configured strategy manager reports `depositsLatched()`
    ///      (`IStrategyManagerRecovery`), set by a strategy force removal. `maxDeposit`/`maxMint` return 0 over
    ///      the same window; withdrawals and redemptions stay open, capped at idle. Cleared by the manager
    ///      admin's `clearDepositLatch()`. The vault admin's `setStrategyManager` also drops it: the latch lives
    ///      in the manager, and a fresh manager starts unlatched, so deposits reopen at once.
    error VaultCoreDepositsLatched(address manager);

    //*//////////////////////////////////////////////////////////////////////////
    //                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the address of the configured strategy manager, or address(0) if none.
    function strategyManager() external view returns (address);

    /// @notice Returns the vault's current idle asset balance (ERC-20 balance of this contract).
    function idleAssets() external view returns (uint256);

    /// @notice Returns the total assets allocated to strategies (totalAssets() - idleAssets()).
    /// @dev Will be 0 when no strategy manager is set. Reverts with {VaultCoreStrategyNavUnavailable}, like
    ///      `totalAssets()`, when the manager's `totalAllocated()` read fails.
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
