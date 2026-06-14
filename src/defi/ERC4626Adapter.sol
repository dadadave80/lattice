// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC4626AdapterLib} from "@lattice/defi/libraries/ERC4626AdapterLib.sol";
import {IERC4626Adapter} from "@lattice/interfaces/IERC4626Adapter.sol";
import {IProtocolAdapter} from "@lattice/interfaces/IProtocolAdapter.sol";
import {IStrategy} from "@lattice/interfaces/external/IStrategy.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

/// @title ERC4626Adapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Diamond facet wrapping any ERC4626 vault (Yearn v3 / MetaMorpho) as a Lattice strategy.
///         Implements `IStrategy` (funds routing), `IProtocolAdapter` (sidecar), and
///         `IERC4626Adapter` (wrap config). NAV via `convertToAssets` (no oracle); supply-only
///         (no leverage). All logic lives in ERC4626AdapterLib.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract ERC4626Adapter is IStrategy, IProtocolAdapter, IERC4626Adapter {
    //*//////////////////////////////////////////////////////////////////////////
    //                              IStrategy
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IStrategy
    function asset() external view virtual override returns (address) {
        return ERC4626AdapterLib.asset();
    }

    /// @inheritdoc IStrategy
    function totalAssetsManaged() external view virtual override returns (uint256) {
        return ERC4626AdapterLib.totalAssetsManaged();
    }

    /// @inheritdoc IStrategy
    function withdraw(uint256 amount, address to) external virtual override returns (uint256 withdrawn) {
        return ERC4626AdapterLib.withdraw(amount, to);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            IProtocolAdapter
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IProtocolAdapter
    function deploy() external virtual override returns (uint256 deployed) {
        return ERC4626AdapterLib.deploy();
    }

    /// @inheritdoc IProtocolAdapter
    function harvest() external virtual override {
        ERC4626AdapterLib.harvest();
    }

    /// @inheritdoc IProtocolAdapter
    function emergencyWithdraw() external virtual override returns (uint256 recovered) {
        return ERC4626AdapterLib.emergencyWithdraw();
    }

    /// @inheritdoc IProtocolAdapter
    function isPaused() external view virtual override returns (bool) {
        return ERC4626AdapterLib.isPaused();
    }

    /// @inheritdoc IProtocolAdapter
    function healthFactor() external view virtual override returns (uint256) {
        return ERC4626AdapterLib.healthFactor();
    }

    /// @inheritdoc IProtocolAdapter
    function minHealthFactor() external view virtual override returns (uint256) {
        return ERC4626AdapterLib.minHealthFactor();
    }

    /// @inheritdoc IProtocolAdapter
    function rewardRecipient() external view virtual override returns (address) {
        return ERC4626AdapterLib.rewardRecipient();
    }

    /// @notice True while a guarded op is executing — mirrors StrategyManager so VaultCore can
    ///         reject share-price-sensitive ops mid-deploy/withdraw (read-only reentrancy guard).
    function reentrancyGuardEntered() external view virtual returns (bool) {
        return ReentrancyGuardLib.reentrancyGuardEntered();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            IERC4626Adapter
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IERC4626Adapter
    function targetVault() external view virtual override returns (address) {
        return ERC4626AdapterLib.targetVault();
    }

    /// @inheritdoc IERC4626Adapter
    function vault() external view virtual override returns (address) {
        return ERC4626AdapterLib.vault();
    }

    /// @inheritdoc IERC4626Adapter
    function sideRewardToken() external view virtual override returns (address) {
        return ERC4626AdapterLib.sideRewardToken();
    }

    /// @inheritdoc IERC4626Adapter
    function setSideRewardToken(address token) external virtual override {
        ERC4626AdapterLib.setSideRewardToken(token);
    }

    /// @inheritdoc IERC4626Adapter
    function setRewardRecipient(address recipient) external virtual override {
        ERC4626AdapterLib.setRewardRecipient(recipient);
    }
}
