// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CompoundV3AdapterLib} from "@lattice/defi/libraries/CompoundV3AdapterLib.sol";
import {IAdapterOperator} from "@lattice/interfaces/defi/IAdapterOperator.sol";
import {ICompoundV3Adapter} from "@lattice/interfaces/defi/ICompoundV3Adapter.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {IStrategy} from "@lattice/interfaces/external/yearn/IStrategy.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

/// @title CompoundV3Adapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Compound V3 (https://github.com/compound-finance/comet)
/// @notice Diamond facet adapting a Compound v3 (Comet) base-asset supply position into a Lattice
///         vault strategy. Implements `IStrategy` (funds routing), `IProtocolAdapter` (sidecar),
///         and `ICompoundV3Adapter` (Comet config). Supply-only (no leverage); 1:1 base accounting,
///         no oracle. All logic lives in CompoundV3AdapterLib.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract CompoundV3Adapter is IStrategy, IProtocolAdapter, IAdapterOperator, ICompoundV3Adapter {
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

    //*//////////////////////////////////////////////////////////////////////////
    //                            IAdapterOperator
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IAdapterOperator
    function setOperator(address operator_) external virtual override {
        CompoundV3AdapterLib.setOperator(operator_);
    }

    /// @inheritdoc IAdapterOperator
    function operator() external view virtual override returns (address) {
        return CompoundV3AdapterLib.operator();
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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect CompoundV3Adapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `asset()` 0x38d52e0f
    ///      `comet()` 0xba3e9c12
    ///      `cometRewards()` 0x32315972
    ///      `deploy()` 0x775c300c
    ///      `emergencyWithdraw()` 0xdb2e21bc
    ///      `harvest()` 0x4641257d
    ///      `healthFactor()` 0x22841f01
    ///      `isPaused()` 0xb187bd26
    ///      `minHealthFactor()` 0xe1b4264c
    ///      `operator()` 0x570ca735
    ///      `reentrancyGuardEntered()` 0xd2c725e0
    ///      `rewardRecipient()` 0x17f33340
    ///      `setCometRewards(address)` 0x36cbb3c3
    ///      `setOperator(address)` 0xb3ab15fb
    ///      `setRewardRecipient(address)` 0xe521136f
    ///      `totalAssetsManaged()` 0x613c822b
    ///      `vault()` 0xfbfa77cf
    ///      `withdraw(uint256,address)` 0x00f714ce
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors =
            hex"38d52e0fba3e9c1232315972775c300cdb2e21bc4641257d22841f01b187bd26e1b4264c570ca735d2c725e017f3334036cbb3c3b3ab15fbe521136f613c822bfbfa77cf00f714ce";
    }
}
