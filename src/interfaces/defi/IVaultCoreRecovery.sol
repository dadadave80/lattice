// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IVaultCoreRecovery
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Vault-side deposit latch of the VaultCore facet, set by a strategy-manager swap that may strand funds
///         and cleared by the vault admin.
/// @dev The strategy manager's own latch (`IStrategyManagerRecovery.depositsLatched`) lives in the manager, so a
///      swap would drop it, and a swap away from a manager whose strategies still hold funds drops those funds
///      from the vault's NAV. Either way, funds the old manager's strategies return later are a plain donation,
///      and a depositor who entered at the lower NAV would capture part of them from the existing holders (#305).
///      `IVaultCore.setStrategyManager` therefore latches deposits closed on the vault unless the old manager
///      verifiably reports both `depositsLatched() == false` and `totalAllocated() == 0`. A read that reverts,
///      returns fewer than 32 bytes or runs out of gas counts as "may strand funds": the swap is the last-resort
///      recovery when the old manager's NAV read is broken, and a manager that cannot answer cannot show that
///      nothing is stranded. On that route the old manager still reports allocations (an overflowing strategy
///      reports up to `type(uint256).max`) or its own sum overflows and the read fails; both latch. The reads
///      never revert the swap. Setting the first manager, or setting the same manager again, latches nothing.
///      While {managerSwapLatched} is true, VaultCore's `deposit`/`mint` revert with
///      `IVaultCore.VaultCoreDepositsLatched(vault)` and `maxDeposit`/`maxMint` return 0; withdrawals and
///      redemptions stay open, capped at idle. The latch survives later swaps and holds until the vault admin
///      calls {clearManagerSwapLatch}. It is independent of the configured manager's own latch: deposits open only
///      when both are clear.
///      Kept apart from `IVaultCore` so that interface's ERC-165 id stays `0xa86d8962`.
interface IVaultCoreRecovery {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  EVENTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Emitted (before `IVaultCore.StrategyManagerSet`) when a swap away from `previousManager` latches
    ///      deposits closed. Emitted on every such swap, including one made while the latch is already set.
    event ManagerSwapLatchSet(address indexed previousManager);

    /// @dev Emitted when `account` clears the manager-swap latch.
    event ManagerSwapLatchCleared(address indexed account);

    //*//////////////////////////////////////////////////////////////////////////
    //                                  ERRORS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Reverts when {clearManagerSwapLatch} is called while the latch is not set.
    error VaultCoreManagerSwapLatchNotSet();

    //*//////////////////////////////////////////////////////////////////////////
    //                                FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns true while a strategy-manager swap keeps the vault's deposits closed.
    /// @dev Reports the vault-side latch only. The configured manager's own latch closes deposits too; read
    ///      `maxDeposit` for the combined state.
    function managerSwapLatched() external view returns (bool);

    /// @notice Clears the manager-swap latch. Admin-only (DEFAULT_ADMIN_ROLE, the role that gates
    ///         `setStrategyManager`).
    /// @dev Clear it once the old manager's stranded funds are back in the vault or written off: deposits then
    ///      price on a NAV that no longer moves when those funds return. Deposits stay closed while the
    ///      configured manager's own latch is set. Reverts with {VaultCoreManagerSwapLatchNotSet} if the latch is
    ///      not set.
    function clearManagerSwapLatch() external;
}
