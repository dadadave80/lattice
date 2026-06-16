// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CurveStableSwapAdapterLib} from "@lattice/defi/libraries/CurveStableSwapAdapterLib.sol";
import {IAdapterOperator} from "@lattice/interfaces/IAdapterOperator.sol";
import {ICurveStableSwapAdapter} from "@lattice/interfaces/ICurveStableSwapAdapter.sol";
import {IProtocolAdapter} from "@lattice/interfaces/IProtocolAdapter.sol";
import {IStrategy} from "@lattice/interfaces/external/IStrategy.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

/// @title CurveStableSwapAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Diamond facet adapting a single-sided Curve StableSwap LP position into a Lattice vault
///         strategy. Implements `IStrategy` (funds routing), `IProtocolAdapter` (sidecar), and
///         `ICurveStableSwapAdapter` (Curve config). Deposits the configured `asset` into one side
///         of a 2-coin pool, holds or stakes the LP, and values it via `get_virtual_price`. CRV
///         rewards are forwarded RAW (swap-free) and excluded from NAV. All logic lives in
///         CurveStableSwapAdapterLib.
/// @dev Provenance: Curve StableSwap (https://github.com/curvefi/curve-contract) +
///      Curve LiquidityGauge (https://github.com/curvefi/curve-dao-contracts).
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract CurveStableSwapAdapter is IStrategy, IProtocolAdapter, IAdapterOperator, ICurveStableSwapAdapter {
    //*//////////////////////////////////////////////////////////////////////////
    //                              IStrategy
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IStrategy
    function asset() external view virtual override returns (address) {
        return CurveStableSwapAdapterLib.asset();
    }

    /// @inheritdoc IStrategy
    function totalAssetsManaged() external view virtual override returns (uint256) {
        return CurveStableSwapAdapterLib.totalAssetsManaged();
    }

    /// @inheritdoc IStrategy
    function withdraw(uint256 amount, address to) external virtual override returns (uint256 withdrawn) {
        return CurveStableSwapAdapterLib.withdraw(amount, to);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            IProtocolAdapter
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IProtocolAdapter
    function deploy() external virtual override returns (uint256 deployed) {
        return CurveStableSwapAdapterLib.deploy();
    }

    /// @inheritdoc IProtocolAdapter
    function harvest() external virtual override {
        CurveStableSwapAdapterLib.harvest();
    }

    /// @inheritdoc IProtocolAdapter
    function emergencyWithdraw() external virtual override returns (uint256 recovered) {
        return CurveStableSwapAdapterLib.emergencyWithdraw();
    }

    /// @inheritdoc IProtocolAdapter
    function isPaused() external view virtual override returns (bool) {
        return CurveStableSwapAdapterLib.isPaused();
    }

    /// @inheritdoc IProtocolAdapter
    function healthFactor() external view virtual override returns (uint256) {
        return CurveStableSwapAdapterLib.healthFactor();
    }

    /// @inheritdoc IProtocolAdapter
    function minHealthFactor() external view virtual override returns (uint256) {
        return CurveStableSwapAdapterLib.minHealthFactor();
    }

    /// @inheritdoc IProtocolAdapter
    function rewardRecipient() external view virtual override returns (address) {
        return CurveStableSwapAdapterLib.rewardRecipient();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            IAdapterOperator
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IAdapterOperator
    function setOperator(address operator_) external virtual override {
        CurveStableSwapAdapterLib.setOperator(operator_);
    }

    /// @inheritdoc IAdapterOperator
    function operator() external view virtual override returns (address) {
        return CurveStableSwapAdapterLib.operator();
    }

    /// @notice True while a guarded op is executing — mirrors StrategyManager so VaultCore can
    ///         reject share-price-sensitive ops mid-deploy/withdraw (read-only reentrancy guard).
    function reentrancyGuardEntered() external view virtual returns (bool) {
        return ReentrancyGuardLib.reentrancyGuardEntered();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         ICurveStableSwapAdapter
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc ICurveStableSwapAdapter
    function pool() external view virtual override returns (address) {
        return CurveStableSwapAdapterLib.pool();
    }

    /// @inheritdoc ICurveStableSwapAdapter
    function lpToken() external view virtual override returns (address) {
        return CurveStableSwapAdapterLib.lpToken();
    }

    /// @inheritdoc ICurveStableSwapAdapter
    function gauge() external view virtual override returns (address) {
        return CurveStableSwapAdapterLib.gauge();
    }

    /// @inheritdoc ICurveStableSwapAdapter
    function crvToken() external view virtual override returns (address) {
        return CurveStableSwapAdapterLib.crvToken();
    }

    /// @inheritdoc ICurveStableSwapAdapter
    function vault() external view virtual override returns (address) {
        return CurveStableSwapAdapterLib.vault();
    }

    /// @inheritdoc ICurveStableSwapAdapter
    function coinIndex() external view virtual override returns (int128) {
        return CurveStableSwapAdapterLib.coinIndex();
    }

    /// @inheritdoc ICurveStableSwapAdapter
    function slippageBps() external view virtual override returns (uint256) {
        return CurveStableSwapAdapterLib.slippageBps();
    }

    /// @inheritdoc ICurveStableSwapAdapter
    function setGauge(address gauge_) external virtual override {
        CurveStableSwapAdapterLib.setGauge(gauge_);
    }

    /// @inheritdoc ICurveStableSwapAdapter
    function setCrvToken(address token) external virtual override {
        CurveStableSwapAdapterLib.setCrvToken(token);
    }

    /// @inheritdoc ICurveStableSwapAdapter
    function setSlippageBps(uint256 slippageBps_) external virtual override {
        CurveStableSwapAdapterLib.setSlippageBps(slippageBps_);
    }

    /// @inheritdoc ICurveStableSwapAdapter
    function setRewardRecipient(address recipient) external virtual override {
        CurveStableSwapAdapterLib.setRewardRecipient(recipient);
    }
}
