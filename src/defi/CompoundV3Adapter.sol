// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CompoundV3AdapterLib} from "@lattice/defi/libraries/CompoundV3AdapterLib.sol";
import {ICompoundV3Adapter} from "@lattice/interfaces/ICompoundV3Adapter.sol";
import {IProtocolAdapter} from "@lattice/interfaces/IProtocolAdapter.sol";
import {IStrategy} from "@lattice/interfaces/external/IStrategy.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

/// @title CompoundV3Adapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Diamond facet adapting a Compound v3 (Comet) base-asset supply position into a Lattice
///         vault strategy. Implements `IStrategy` (funds routing), `IProtocolAdapter` (sidecar),
///         and `ICompoundV3Adapter` (Comet config). Supply-only (no leverage); 1:1 base accounting,
///         no oracle. All logic lives in CompoundV3AdapterLib.
contract CompoundV3Adapter is IStrategy, IProtocolAdapter, ICompoundV3Adapter {
    //*//////////////////////////////////////////////////////////////////////////
    //                              IStrategy
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IStrategy
    function asset() external view virtual override returns (address) {
        return CompoundV3AdapterLib.asset();
    }

    /// @inheritdoc IStrategy
    function totalAssetsManaged() external view virtual override returns (uint256) {
        return CompoundV3AdapterLib.totalAssetsManaged();
    }

    /// @inheritdoc IStrategy
    function withdraw(uint256 amount, address to) external virtual override returns (uint256 withdrawn) {
        return CompoundV3AdapterLib.withdraw(amount, to);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            IProtocolAdapter
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IProtocolAdapter
    function deploy() external virtual override returns (uint256 deployed) {
        return CompoundV3AdapterLib.deploy();
    }

    /// @inheritdoc IProtocolAdapter
    function harvest() external virtual override {
        CompoundV3AdapterLib.harvest();
    }

    /// @inheritdoc IProtocolAdapter
    function emergencyWithdraw() external virtual override returns (uint256 recovered) {
        return CompoundV3AdapterLib.emergencyWithdraw();
    }

    /// @inheritdoc IProtocolAdapter
    function isPaused() external view virtual override returns (bool) {
        return CompoundV3AdapterLib.isPaused();
    }

    /// @inheritdoc IProtocolAdapter
    function healthFactor() external view virtual override returns (uint256) {
        return CompoundV3AdapterLib.healthFactor();
    }

    /// @inheritdoc IProtocolAdapter
    function minHealthFactor() external view virtual override returns (uint256) {
        return CompoundV3AdapterLib.minHealthFactor();
    }

    /// @inheritdoc IProtocolAdapter
    function rewardRecipient() external view virtual override returns (address) {
        return CompoundV3AdapterLib.rewardRecipient();
    }

    /// @notice True while a guarded op is executing — mirrors StrategyManager so VaultCore can
    ///         reject share-price-sensitive ops mid-deploy/withdraw (read-only reentrancy guard).
    function reentrancyGuardEntered() external view virtual returns (bool) {
        return ReentrancyGuardLib.reentrancyGuardEntered();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            ICompoundV3Adapter
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc ICompoundV3Adapter
    function comet() external view virtual override returns (address) {
        return CompoundV3AdapterLib.comet();
    }

    /// @inheritdoc ICompoundV3Adapter
    function vault() external view virtual override returns (address) {
        return CompoundV3AdapterLib.vault();
    }

    /// @inheritdoc ICompoundV3Adapter
    function cometRewards() external view virtual override returns (address) {
        return CompoundV3AdapterLib.cometRewards();
    }

    /// @inheritdoc ICompoundV3Adapter
    function setCometRewards(address rewards) external virtual override {
        CompoundV3AdapterLib.setCometRewards(rewards);
    }

    /// @inheritdoc ICompoundV3Adapter
    function setRewardRecipient(address recipient) external virtual override {
        CompoundV3AdapterLib.setRewardRecipient(recipient);
    }
}
