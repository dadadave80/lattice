// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LidoAdapterLib} from "@lattice/defi/libraries/LidoAdapterLib.sol";
import {IAdapterOperator} from "@lattice/interfaces/defi/IAdapterOperator.sol";
import {ILidoAdapter} from "@lattice/interfaces/defi/ILidoAdapter.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {IStrategy} from "@lattice/interfaces/external/yearn/IStrategy.sol";
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
///      canonical WETH9 (https://github.com/gnosis/canonical-weth). The facet's own payable
///      `receive()` serves STANDALONE hosting only — behind a diamond, empty-calldata ETH routes to the
///      cut {Receive} facet, and the WETH unwrap goes through the stipend-safe {WETHUnwrapper}.
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

    /// @notice Accepts native ETH when hosted STANDALONE (unwrapper return, Lido queue payout). Behind a
    ///         diamond this is never dispatched — the diamond's zero-selector route runs the {Receive}
    ///         facet instead. No logic: the calling library re-wraps the ETH into WETH.
    receive() external payable {}

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect LidoAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. `receive()` has no selector and is not exported (it serves standalone
    ///      hosting only; see the contract NatSpec). Chunks:
    ///      `asset()` 0x38d52e0f
    ///      `bufferBalance()` 0x1298f13c
    ///      `claimWithdrawal(uint256)` 0xf8444436
    ///      `deploy()` 0x775c300c
    ///      `emergencyWithdraw()` 0xdb2e21bc
    ///      `harvest()` 0x4641257d
    ///      `harvestToken(address)` 0x0bb18dc1
    ///      `healthFactor()` 0x22841f01
    ///      `isPaused()` 0xb187bd26
    ///      `lido()` 0x23509a2d
    ///      `minHealthFactor()` 0xe1b4264c
    ///      `operator()` 0x570ca735
    ///      `pendingRequestAt(uint256)` 0x978e5f31
    ///      `pendingRequestCount()` 0xe0abba57
    ///      `pendingWithdrawalAssets()` 0xb5149a61
    ///      `reentrancyGuardEntered()` 0xd2c725e0
    ///      `requestWithdrawal(uint256)` 0x9ee679e8
    ///      `rewardRecipient()` 0x17f33340
    ///      `setOperator(address)` 0xb3ab15fb
    ///      `setRewardRecipient(address)` 0xe521136f
    ///      `stakedWstETH()` 0x4aedacb4
    ///      `totalAssetsManaged()` 0x613c822b
    ///      `vault()` 0xfbfa77cf
    ///      `weth()` 0x3fc8cef3
    ///      `withdraw(uint256,address)` 0x00f714ce
    ///      `withdrawalQueue()` 0x37d5fe99
    ///      `wstETH()` 0x4aa07e64
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors =
            hex"38d52e0f1298f13cf8444436775c300cdb2e21bc4641257d0bb18dc122841f01b187bd2623509a2de1b4264c570ca735978e5f31e0abba57b5149a61d2c725e09ee679e817f33340b3ab15fbe521136f4aedacb4613c822bfbfa77cf3fc8cef300f714ce37d5fe994aa07e64";
    }
}
