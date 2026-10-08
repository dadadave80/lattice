// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IStrategyManagerRecovery
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Deposit latch of the StrategyManager facet, set by a force removal and cleared by the admin.
/// @dev A force removal (`removeStrategy` on a strategy whose `totalAssetsManaged()` read fails) drops the
///      strategy's funds from the vault's NAV. Any of those funds that later return to the vault are a plain
///      donation, so a depositor who entered at the lower NAV would capture part of them from the existing
///      holders (#270). The removal therefore latches deposits closed: while {depositsLatched} is true,
///      VaultCore's `deposit`/`mint` revert with `IVaultCore.VaultCoreDepositsLatched` and its
///      `maxDeposit`/`maxMint` return 0. Withdrawals and redemptions stay open, capped at idle as usual. The
///      admin clears the latch once the stranded funds are recovered or written off. Returned funds accrue to
///      whoever still holds shares when they return; a holder who exits while latched is priced on the
///      idle-only NAV and gives up their share of them.
///      The latch lives in this manager, so the vault admin's `IVaultCore.setStrategyManager` drops it: a fresh
///      manager starts unlatched and the vault reopens deposits at once.
///      Kept apart from {IStrategyManager} so that interface's ERC-165 id stays `0xcce4011b`.
interface IStrategyManagerRecovery {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  EVENTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Emitted (after `StrategyForceRemoved`) when a force removal of `strategy` latches deposits closed.
    ///      Emitted on every force removal, including one made while the latch is already set.
    event DepositLatchSet(address indexed strategy);

    /// @dev Emitted when `account` clears the deposit latch, reopening deposits.
    event DepositLatchCleared(address indexed account);

    //*//////////////////////////////////////////////////////////////////////////
    //                                  ERRORS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Reverts when {clearDepositLatch} is called while deposits are not latched.
    error StrategyManagerDepositLatchNotSet();

    //*//////////////////////////////////////////////////////////////////////////
    //                                FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns true while a force removal keeps the vault's deposits closed.
    function depositsLatched() external view returns (bool);

    /// @notice Clears the deposit latch, reopening the vault's deposits. Admin-only (DEFAULT_ADMIN_ROLE, the role
    ///         that gates `removeStrategy`).
    /// @dev Clear it once the force-removed strategy's funds are back in the vault or written off: deposits then
    ///      price on a NAV that no longer moves when those funds return. Reverts with
    ///      {StrategyManagerDepositLatchNotSet} if the latch is not set.
    function clearDepositLatch() external;
}
