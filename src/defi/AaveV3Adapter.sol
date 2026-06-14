// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AaveV3AdapterLib} from "@lattice/defi/libraries/AaveV3AdapterLib.sol";
import {IAaveV3Adapter} from "@lattice/interfaces/IAaveV3Adapter.sol";
import {IProtocolAdapter} from "@lattice/interfaces/IProtocolAdapter.sol";
import {IStrategy} from "@lattice/interfaces/external/IStrategy.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

/// @title AaveV3Adapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Diamond facet adapting an Aave v3 supply (+ optional leverage) position into a Lattice
///         vault strategy. Implements `IStrategy` (funds routing), `IProtocolAdapter` (sidecar),
///         and `IAaveV3Adapter` (Aave config). All logic lives in AaveV3AdapterLib.
contract AaveV3Adapter is IStrategy, IProtocolAdapter, IAaveV3Adapter {
    //*//////////////////////////////////////////////////////////////////////////
    //                              IStrategy
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IStrategy
    function asset() external view virtual override returns (address) {
        return AaveV3AdapterLib.asset();
    }

    /// @inheritdoc IStrategy
    function totalAssetsManaged() external view virtual override returns (uint256) {
        return AaveV3AdapterLib.totalAssetsManaged();
    }

    /// @inheritdoc IStrategy
    function withdraw(uint256 amount, address to) external virtual override returns (uint256 withdrawn) {
        return AaveV3AdapterLib.withdraw(amount, to);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            IProtocolAdapter
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IProtocolAdapter
    function deploy() external virtual override returns (uint256 deployed) {
        return AaveV3AdapterLib.deploy();
    }

    /// @inheritdoc IProtocolAdapter
    function harvest() external virtual override {
        AaveV3AdapterLib.harvest();
    }

    /// @inheritdoc IProtocolAdapter
    function emergencyWithdraw() external virtual override returns (uint256 recovered) {
        return AaveV3AdapterLib.emergencyWithdraw();
    }

    /// @inheritdoc IProtocolAdapter
    function isPaused() external view virtual override returns (bool) {
        return AaveV3AdapterLib.isPaused();
    }

    /// @inheritdoc IProtocolAdapter
    function healthFactor() external view virtual override returns (uint256) {
        return AaveV3AdapterLib.healthFactor();
    }

    /// @inheritdoc IProtocolAdapter
    function minHealthFactor() external view virtual override returns (uint256) {
        return AaveV3AdapterLib.minHealthFactor();
    }

    /// @inheritdoc IProtocolAdapter
    function rewardRecipient() external view virtual override returns (address) {
        return AaveV3AdapterLib.rewardRecipient();
    }

    /// @notice True while a guarded op is executing — mirrors StrategyManager so VaultCore can
    ///         reject share-price-sensitive ops mid-deploy/withdraw (read-only reentrancy guard).
    function reentrancyGuardEntered() external view virtual returns (bool) {
        return ReentrancyGuardLib.reentrancyGuardEntered();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            IAaveV3Adapter
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IAaveV3Adapter
    function addressesProvider() external view virtual override returns (address) {
        return AaveV3AdapterLib.addressesProvider();
    }

    /// @inheritdoc IAaveV3Adapter
    function aToken() external view virtual override returns (address) {
        return AaveV3AdapterLib.aToken();
    }

    /// @inheritdoc IAaveV3Adapter
    function vault() external view virtual override returns (address) {
        return AaveV3AdapterLib.vault();
    }

    /// @inheritdoc IAaveV3Adapter
    function eModeCategory() external view virtual override returns (uint8) {
        return AaveV3AdapterLib.eModeCategory();
    }

    /// @inheritdoc IAaveV3Adapter
    function rewardsController() external view virtual override returns (address) {
        return AaveV3AdapterLib.rewardsController();
    }

    /// @inheritdoc IAaveV3Adapter
    function setEMode(uint8 categoryId) external virtual override {
        AaveV3AdapterLib.setEMode(categoryId);
    }

    /// @inheritdoc IAaveV3Adapter
    function setMinHealthFactor(uint256 minHealthFactorWad) external virtual override {
        AaveV3AdapterLib.setMinHealthFactor(minHealthFactorWad);
    }

    /// @inheritdoc IAaveV3Adapter
    function setRewardRecipient(address recipient) external virtual override {
        AaveV3AdapterLib.setRewardRecipient(recipient);
    }

    /// @inheritdoc IAaveV3Adapter
    function setRewardsController(address controller) external virtual override {
        AaveV3AdapterLib.setRewardsController(controller);
    }

    /// @inheritdoc IAaveV3Adapter
    function lever(uint256 borrowAmount) external virtual override {
        AaveV3AdapterLib.lever(borrowAmount);
    }

    /// @inheritdoc IAaveV3Adapter
    function delever(uint256 collateralToPull) external virtual override returns (uint256 repaid) {
        return AaveV3AdapterLib.delever(collateralToPull);
    }
}
