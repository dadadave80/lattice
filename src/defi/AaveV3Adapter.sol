// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AaveV3AdapterLib} from "@lattice/defi/libraries/AaveV3AdapterLib.sol";
import {IAaveV3Adapter} from "@lattice/interfaces/defi/IAaveV3Adapter.sol";
import {IAdapterOperator} from "@lattice/interfaces/defi/IAdapterOperator.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {IStrategy} from "@lattice/interfaces/external/yearn/IStrategy.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

/// @title AaveV3Adapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Aave V3 (https://github.com/aave-dao/aave-v3-origin)
/// @notice Diamond facet adapting an Aave v3 supply (+ optional leverage) position into a Lattice
///         vault strategy. Implements `IStrategy` (funds routing), `IProtocolAdapter` (sidecar),
///         and `IAaveV3Adapter` (Aave config). All logic lives in AaveV3AdapterLib.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract AaveV3Adapter is IStrategy, IProtocolAdapter, IAdapterOperator, IAaveV3Adapter {
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

    //*//////////////////////////////////////////////////////////////////////////
    //                            IAdapterOperator
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IAdapterOperator
    function setOperator(address operator_) external virtual override {
        AaveV3AdapterLib.setOperator(operator_);
    }

    /// @inheritdoc IAdapterOperator
    function operator() external view virtual override returns (address) {
        return AaveV3AdapterLib.operator();
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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect AaveV3Adapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `aToken()` 0xa0c1f15e
    ///      `addressesProvider()` 0xc72c4d10
    ///      `asset()` 0x38d52e0f
    ///      `delever(uint256)` 0xcf60112b
    ///      `deploy()` 0x775c300c
    ///      `eModeCategory()` 0xa6e40bec
    ///      `emergencyWithdraw()` 0xdb2e21bc
    ///      `harvest()` 0x4641257d
    ///      `healthFactor()` 0x22841f01
    ///      `isPaused()` 0xb187bd26
    ///      `lever(uint256)` 0x9dcc380a
    ///      `minHealthFactor()` 0xe1b4264c
    ///      `operator()` 0x570ca735
    ///      `reentrancyGuardEntered()` 0xd2c725e0
    ///      `rewardRecipient()` 0x17f33340
    ///      `rewardsController()` 0x6bb65f53
    ///      `setEMode(uint8)` 0xb94e11c6
    ///      `setMinHealthFactor(uint256)` 0x01b08d58
    ///      `setOperator(address)` 0xb3ab15fb
    ///      `setRewardRecipient(address)` 0xe521136f
    ///      `setRewardsController(address)` 0xbee36bb3
    ///      `totalAssetsManaged()` 0x613c822b
    ///      `vault()` 0xfbfa77cf
    ///      `withdraw(uint256,address)` 0x00f714ce
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors =
            hex"a0c1f15ec72c4d1038d52e0fcf60112b775c300ca6e40becdb2e21bc4641257d22841f01b187bd269dcc380ae1b4264c570ca735d2c725e017f333406bb65f53b94e11c601b08d58b3ab15fbe521136fbee36bb3613c822bfbfa77cf00f714ce";
    }
}
