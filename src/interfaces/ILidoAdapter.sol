// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ILidoAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Lido-staking-specific config + keeper ABI. The adapter also implements `IStrategy` +
///         `IProtocolAdapter`. The asset is **WETH** (so the position fits the ERC-20 `IStrategy`
///         surface); native ETH is only an intermediate hop.
///
///         **Buffer model (async-withdraw protocol).** Lido withdrawals are an async queue and the
///         underlying is native ETH, which breaks the synchronous, ERC-20 withdraw assumption every
///         other adapter relies on. This adapter therefore splits withdrawals into two legs:
///         - the synchronous `IStrategy.withdraw` is served **only** from an idle WETH buffer and is
///           shortfall-honest (returns less when the buffer is short; the StrategyManager's
///           shortfall check upstream handles the remainder);
///         - the slow Lido-queue leg runs out-of-band via the keeper functions `requestWithdrawal`
///           (wstETH → stETH → enqueue) and `claimWithdrawal` (finalized request → ETH → refill the
///           WETH buffer).
///
///         **Valuation.** stETH is valued 1:1 with ETH/WETH per Lido's own accounting. A stETH/ETH
///         secondary-market de-peg is **not** oracle-corrected here — `totalAssetsManaged` trusts
///         Lido's `getStETHByWstETH` rate. A future oracle hook (haircut on a de-peg) is a follow-up.
interface ILidoAdapter {
    /// @notice Emitted once at init with the core wiring.
    /// @param weth   The WETH token (the adapter's asset + idle buffer).
    /// @param lido   The Lido stETH token.
    /// @param wstETH The wstETH wrapper the staked position is held as.
    /// @param vault  The Lattice vault funds are returned to.
    event LidoAdapterConfigured(address indexed weth, address indexed lido, address indexed wstETH, address vault);

    /// @notice Emitted when a wstETH tranche is unwrapped and enqueued in the Lido withdrawal queue.
    /// @param requestId   The Lido withdrawal-request id created.
    /// @param stETHAmount The stETH amount locked for the request (recorded as pending in NAV).
    event WithdrawalRequested(uint256 indexed requestId, uint256 stETHAmount);

    /// @notice Emitted when a finalized withdrawal request is claimed and the ETH wrapped into the buffer.
    /// @param requestId   The Lido withdrawal-request id claimed.
    /// @param ethReceived The native ETH received from the queue (wrapped 1:1 into the WETH buffer).
    event WithdrawalClaimed(uint256 indexed requestId, uint256 ethReceived);

    /// @dev The reward recipient is announced via `IProtocolAdapter.RewardRecipientSet` (shared with
    ///      the generic adapter ABI) — not redeclared here to avoid an event-name collision when the
    ///      facet inherits both interfaces.

    /// @notice A Lido `submit` returned no stETH (zero-mint), so there was nothing to stake.
    error LidoAdapterNothingStaked();

    /// @notice The supplied wstETH amount to enqueue exceeds the adapter's wstETH balance.
    error LidoAdapterInsufficientWstETH(uint256 requested, uint256 available);

    /// @notice The supplied request id is not tracked as a pending withdrawal of this adapter.
    error LidoAdapterUnknownRequest(uint256 requestId);

    /// @notice Returns the WETH token (the adapter's asset and idle buffer).
    function weth() external view returns (address);

    /// @notice Returns the Lido stETH token.
    function lido() external view returns (address);

    /// @notice Returns the wstETH wrapper the staked position is held as.
    function wstETH() external view returns (address);

    /// @notice Returns the Lido withdrawal queue the slow leg routes through.
    function withdrawalQueue() external view returns (address);

    /// @notice Returns the Lattice vault funds are returned to on withdraw/emergency.
    function vault() external view returns (address);

    /// @notice Returns the idle WETH buffer balance the synchronous `withdraw` is served from.
    function bufferBalance() external view returns (uint256);

    /// @notice Returns the wstETH balance currently staked in Lido.
    function stakedWstETH() external view returns (uint256);

    /// @notice Returns the total stETH currently sitting in pending (unclaimed) withdrawal requests.
    /// @dev Counted in NAV so funds in-flight through the queue are not lost from accounting.
    function pendingWithdrawalAssets() external view returns (uint256);

    /// @notice Returns the number of pending (unclaimed) withdrawal requests.
    function pendingRequestCount() external view returns (uint256);

    /// @notice Returns the pending withdrawal-request id at `index`.
    function pendingRequestAt(uint256 index) external view returns (uint256);

    /// @notice Unwraps `wstAmount` of wstETH to stETH and enqueues it in the Lido withdrawal queue
    ///         (admin/keeper). Records the resulting request id + stETH amount as pending so NAV is
    ///         unchanged by the move. The ETH is claimable later via `claimWithdrawal`.
    /// @param wstAmount The amount of wstETH to unwrap and enqueue.
    /// @return requestId The Lido withdrawal-request id created.
    function requestWithdrawal(uint256 wstAmount) external returns (uint256 requestId);

    /// @notice Claims a finalized withdrawal request (permissionless/keeper): pulls the owed ETH from
    ///         the queue and wraps it 1:1 into the WETH buffer, clearing the request from pending.
    /// @param requestId The id of the finalized pending request to claim.
    /// @return ethReceived The native ETH claimed and wrapped into the buffer.
    function claimWithdrawal(uint256 requestId) external returns (uint256 ethReceived);

    /// @notice Sets the reward recipient (admin only). Lido yield accrues in the wstETH→stETH rate,
    ///         not a claimable reward token, so this only governs stray-token sweeps in `harvest()`.
    function setRewardRecipient(address recipient) external;
}
