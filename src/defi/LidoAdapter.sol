// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LidoAdapterLib} from "@lattice/defi/libraries/LidoAdapterLib.sol";
import {IAdapterOperator} from "@lattice/interfaces/defi/IAdapterOperator.sol";
import {ILidoAdapter} from "@lattice/interfaces/defi/ILidoAdapter.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {IStrategy} from "@lattice/interfaces/external/IStrategy.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

/// @title LidoAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Lido (https://github.com/lidofinance/core)
/// @notice Diamond facet adapting a Lido staking position into a Lattice vault strategy under the
///         **buffer model**. Implements `IStrategy` (funds routing), `IProtocolAdapter` (sidecar),
///         and `ILidoAdapter` (Lido config + async-queue keeper). The asset is **WETH**; native ETH
///         is only an intermediate hop (WETH → ETH → stETH → wstETH on deploy, and the reverse on
///         the async exit). Because Lido withdrawals are an async queue, the synchronous
///         `IStrategy.withdraw` is served from an idle WETH buffer and is shortfall-honest; the slow
///         Lido-queue exit runs out-of-band via `requestWithdrawal` / `claimWithdrawal`. All logic
///         lives in LidoAdapterLib.
/// @dev Provenance: Lido stETH / wstETH / WithdrawalQueue (https://github.com/lidofinance/lido-dao) +
///      canonical WETH9 (https://github.com/gnosis/canonical-weth). The facet exposes a payable
///      `receive()` so it can take native ETH from `WETH.withdraw` and from the Lido queue's claim.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract LidoAdapter is IStrategy, IProtocolAdapter, IAdapterOperator, ILidoAdapter {
    //*//////////////////////////////////////////////////////////////////////////
    //                              IStrategy
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IStrategy
    function asset() external view virtual override returns (address) {
        return LidoAdapterLib.asset();
    }

    /// @inheritdoc IStrategy
    function totalAssetsManaged() external view virtual override returns (uint256) {
        return LidoAdapterLib.totalAssetsManaged();
    }

    /// @inheritdoc IStrategy
    function withdraw(uint256 amount, address to) external virtual override returns (uint256 withdrawn) {
        return LidoAdapterLib.withdraw(amount, to);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            IProtocolAdapter
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IProtocolAdapter
    function deploy() external virtual override returns (uint256 deployed) {
        return LidoAdapterLib.deploy();
    }

    /// @inheritdoc IProtocolAdapter
    /// @dev No-op: Lido yield accrues in the wstETH→stETH rate (already in NAV), not a claimable
    ///      reward token. Use `harvestToken` to forward a specific stray (airdropped) token.
    function harvest() external virtual override {
        LidoAdapterLib.harvest();
    }

    /// @inheritdoc IProtocolAdapter
    function emergencyWithdraw() external virtual override returns (uint256 recovered) {
        return LidoAdapterLib.emergencyWithdraw();
    }

    /// @inheritdoc IProtocolAdapter
    function isPaused() external view virtual override returns (bool) {
        return LidoAdapterLib.isPaused();
    }

    /// @inheritdoc IProtocolAdapter
    function healthFactor() external view virtual override returns (uint256) {
        return LidoAdapterLib.healthFactor();
    }

    /// @inheritdoc IProtocolAdapter
    function minHealthFactor() external view virtual override returns (uint256) {
        return LidoAdapterLib.minHealthFactor();
    }

    /// @inheritdoc IProtocolAdapter
    function rewardRecipient() external view virtual override returns (address) {
        return LidoAdapterLib.rewardRecipient();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            IAdapterOperator
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IAdapterOperator
    function setOperator(address operator_) external virtual override {
        LidoAdapterLib.setOperator(operator_);
    }

    /// @inheritdoc IAdapterOperator
    function operator() external view virtual override returns (address) {
        return LidoAdapterLib.operator();
    }

    /// @notice True while a guarded op is executing — mirrors StrategyManager so VaultCore can
    ///         reject share-price-sensitive ops mid-deploy/withdraw (read-only reentrancy guard).
    function reentrancyGuardEntered() external view virtual returns (bool) {
        return ReentrancyGuardLib.reentrancyGuardEntered();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ILidoAdapter
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc ILidoAdapter
    function weth() external view virtual override returns (address) {
        return LidoAdapterLib.weth();
    }

    /// @inheritdoc ILidoAdapter
    function lido() external view virtual override returns (address) {
        return LidoAdapterLib.lido();
    }

    /// @inheritdoc ILidoAdapter
    function wstETH() external view virtual override returns (address) {
        return LidoAdapterLib.wstETH();
    }

    /// @inheritdoc ILidoAdapter
    function withdrawalQueue() external view virtual override returns (address) {
        return LidoAdapterLib.withdrawalQueue();
    }

    /// @inheritdoc ILidoAdapter
    function vault() external view virtual override returns (address) {
        return LidoAdapterLib.vault();
    }

    /// @inheritdoc ILidoAdapter
    function bufferBalance() external view virtual override returns (uint256) {
        return LidoAdapterLib.bufferBalance();
    }

    /// @inheritdoc ILidoAdapter
    function stakedWstETH() external view virtual override returns (uint256) {
        return LidoAdapterLib.stakedWstETH();
    }

    /// @inheritdoc ILidoAdapter
    function pendingWithdrawalAssets() external view virtual override returns (uint256) {
        return LidoAdapterLib.pendingWithdrawalAssets();
    }

    /// @inheritdoc ILidoAdapter
    function pendingRequestCount() external view virtual override returns (uint256) {
        return LidoAdapterLib.pendingRequestCount();
    }

    /// @inheritdoc ILidoAdapter
    function pendingRequestAt(uint256 index) external view virtual override returns (uint256) {
        return LidoAdapterLib.pendingRequestAt(index);
    }

    /// @inheritdoc ILidoAdapter
    function requestWithdrawal(uint256 wstAmount) external virtual override returns (uint256 requestId) {
        return LidoAdapterLib.requestWithdrawal(wstAmount);
    }

    /// @inheritdoc ILidoAdapter
    function claimWithdrawal(uint256 requestId) external virtual override returns (uint256 ethReceived) {
        return LidoAdapterLib.claimWithdrawal(requestId);
    }

    /// @inheritdoc ILidoAdapter
    function setRewardRecipient(address recipient) external virtual override {
        LidoAdapterLib.setRewardRecipient(recipient);
    }

    /// @notice Forwards the adapter's entire balance of a stray (airdropped) `token` raw to the
    ///         reward recipient (admin/keeper). The three core tokens (WETH/stETH/wstETH) are
    ///         rejected so a sweep can never drain the buffer or the staked position.
    function harvestToken(address token) external virtual {
        LidoAdapterLib.harvestToken(token);
    }

    /// @notice Accepts native ETH from `WETH.withdraw` (deploy) and from the Lido withdrawal queue's
    ///         `claimWithdrawal` payout. No logic: the calling library re-wraps the ETH into WETH.
    receive() external payable {}
}
