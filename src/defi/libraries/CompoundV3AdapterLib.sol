// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {AdapterBaseLib} from "@lattice/defi/libraries/AdapterBaseLib.sol";
import {ICompoundV3Adapter} from "@lattice/interfaces/ICompoundV3Adapter.sol";
import {IProtocolAdapter} from "@lattice/interfaces/IProtocolAdapter.sol";
import {IComet} from "@lattice/interfaces/external/IComet.sol";
import {ICometRewards} from "@lattice/interfaces/external/ICometRewards.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.CompoundV3Adapter")) - 1)) & ~bytes32(uint256(0xff))`.
/// Precomputed: 0x96f5f0ff446cccea8e0037b1046912f9609bac8e9b25707c9fadf78bc2d9fe00
bytes32 constant COMPOUND_V3_ADAPTER_STORAGE_SLOT = 0x96f5f0ff446cccea8e0037b1046912f9609bac8e9b25707c9fadf78bc2d9fe00;

/// @dev ERC-165 storage location (shared across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant COMPOUND_V3_ADAPTER_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x8f7783e6 is `type(IProtocolAdapter).interfaceId` (same value the Aave adapter registers;
/// the ERC-165 map slot is shared because the interface ID is identical).
/// `keccak256(abi.encode(bytes4(0x8f7783e6), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IPROTOCOLADAPTER_SLOT = 0x789387b95720f4aa713e912bc377a2f999f1310b69003727d9c01b7ea1494c77;

/// @dev 0xa01f1203 is `type(ICompoundV3Adapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xa01f1203), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ICOMPOUNDV3ADAPTER_SLOT =
    0x02c9afc8b129398c559418de4825ac6d2670e884630d5a02557a9dcecd0b40e1;

/// @notice ERC-7201 namespaced storage for the Compound v3 (Comet) supply adapter.
/// @custom:storage-location erc7201:lattice.storage.CompoundV3Adapter
struct CompoundV3AdapterStorage {
    /// @dev The Comet market this adapter supplies to.
    address _comet;
    /// @dev The underlying base asset (== Comet base token == vault asset).
    address _asset;
    /// @dev The vault funds are returned to on withdraw/emergency.
    address _vault;
    /// @dev Reward recipient for raw-forwarded COMP.
    address _rewardRecipient;
    /// @dev The CometRewards controller; `harvest()` claims COMP from it.
    address _cometRewards;
    /// @dev Authorized operator: the SOLE caller permitted to invoke `deploy`/`withdraw`/`harvest`
    ///      (the StrategyManager in the live system). Zero until wired ⇒ that trio reverts.
    ///      APPENDED last (append-only ERC-7201 rule — never reorder/insert).
    address _operator;
}

/// @title CompoundV3AdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Logic for the Compound v3 supply adapter. 1:1 base-asset accounting (no oracle).
///         Reentrancy-gated, pause/emergency-aware, shortfall-honest. Rewards forwarded raw.
library CompoundV3AdapterLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function compoundV3AdapterStorage() internal pure returns (CompoundV3AdapterStorage storage $) {
        assembly {
            $.slot := COMPOUND_V3_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    function __CompoundV3Adapter_init(address comet_, address asset_, address vault_, address recipient_) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        if (comet_ == address(0) || asset_ == address(0) || vault_ == address(0) || recipient_ == address(0)) {
            revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        }
        address base = IComet(comet_).baseToken();
        if (base != asset_) revert ICompoundV3Adapter.CompoundV3AdapterBaseAssetMismatch(base, asset_);

        CompoundV3AdapterStorage storage $ = compoundV3AdapterStorage();
        $._comet = comet_;
        $._asset = asset_;
        $._vault = vault_;
        $._rewardRecipient = recipient_;

        registerInterface();
        emit ICompoundV3Adapter.CompoundV3AdapterConfigured(comet_, asset_, vault_);
        emit IProtocolAdapter.RewardRecipientSet(recipient_);
    }

    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IPROTOCOLADAPTER_SLOT, true)
            sstore(ERC165_MAP_ICOMPOUNDV3ADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  VIEWS
    //////////////////////////////////////////////////////////////////////////*//

    function asset() internal view returns (address) {
        return compoundV3AdapterStorage()._asset;
    }

    function vault() internal view returns (address) {
        return compoundV3AdapterStorage()._vault;
    }

    function comet() internal view returns (address) {
        return compoundV3AdapterStorage()._comet;
    }

    function cometRewards() internal view returns (address) {
        return compoundV3AdapterStorage()._cometRewards;
    }

    function rewardRecipient() internal view returns (address) {
        return compoundV3AdapterStorage()._rewardRecipient;
    }

    function operator() internal view returns (address) {
        return compoundV3AdapterStorage()._operator;
    }

    /// @dev Reverts `ProtocolAdapterUnauthorized` unless the caller is the wired operator. Placed at
    ///      the very top of `deploy`/`withdraw`/`harvest` — BEFORE the reentrancy guard — so an
    ///      unauthorized call never leaves the guard latched. Zero operator ⇒ always reverts.
    function _checkOperator() private view {
        if (msg.sender != compoundV3AdapterStorage()._operator) {
            revert IProtocolAdapter.ProtocolAdapterUnauthorized(msg.sender);
        }
    }

    function minHealthFactor() internal pure returns (uint256) {
        return type(uint256).max; // supply-only
    }

    function healthFactor() internal pure returns (uint256) {
        return type(uint256).max; // no debt
    }

    function isPaused() internal view returns (bool) {
        return PausableLib.paused() || EmergencyStopLib.isStopped();
    }

    /// @notice 1:1 base-asset accounting. Comet's `balanceOf` is present-value and already reflects
    ///         accrued interest, so no pre-accrue is needed and this stays `view` (matching the
    ///         `IStrategy.totalAssetsManaged()` `view` signature). No oracle.
    /// @dev **Idle leg (NAV-gap fix):** adds the adapter's idle base-asset balance to the Comet
    ///      position. `IVaultCore.allocateToStrategy` pushes funds here with a bare transfer that does
    ///      NOT supply to Comet, so undeployed funds sit idle until `deploy()`. Counting that idle
    ///      keeps the vault's share price flat across the allocate→deploy window. No double-count: the
    ///      idle is in neither the vault's idle nor the Comet balance, and after `deploy()` idle→~0
    ///      while the Comet balance rises by the same amount, so the sum is invariant across deploy.
    function totalAssetsManaged() internal view returns (uint256) {
        CompoundV3AdapterStorage storage $ = compoundV3AdapterStorage();
        return IComet($._comet).balanceOf(address(this)) + AdapterBaseLib.balanceOfSelf($._asset);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function setCometRewards(address rewards) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (rewards == address(0)) revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        compoundV3AdapterStorage()._cometRewards = rewards;
        emit ICompoundV3Adapter.CometRewardsSet(rewards);
    }

    function setRewardRecipient(address recipient) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (recipient == address(0)) revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        compoundV3AdapterStorage()._rewardRecipient = recipient;
        emit IProtocolAdapter.RewardRecipientSet(recipient);
    }

    /// @notice Sets the authorized operator for `deploy`/`withdraw`/`harvest` (admin-only). Rejects
    ///         `address(0)` so the trio cannot be opened to an unauthenticated default.
    function setOperator(address operator_) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (operator_ == address(0)) revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        compoundV3AdapterStorage()._operator = operator_;
        emit IProtocolAdapter.OperatorSet(operator_);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                SUPPLY LEG
    //////////////////////////////////////////////////////////////////////////*//

    function deploy() internal returns (uint256 deployed) {
        _checkOperator();
        ReentrancyGuardLib.nonReentrantBefore();
        if (isPaused()) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IProtocolAdapter.ProtocolAdapterPaused();
        }
        CompoundV3AdapterStorage storage $ = compoundV3AdapterStorage();
        address asset_ = $._asset;
        uint256 idle = AdapterBaseLib.balanceOfSelf(asset_);
        if (idle == 0) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IProtocolAdapter.ProtocolAdapterNothingToDeploy();
        }
        AdapterBaseLib.forceApprove(asset_, $._comet, idle);
        IComet($._comet).supply(asset_, idle);
        deployed = idle;
        emit IProtocolAdapter.Deployed(asset_, idle);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    function withdraw(uint256 amount, address to) internal returns (uint256 withdrawn) {
        _checkOperator();
        ReentrancyGuardLib.nonReentrantBefore();
        CompoundV3AdapterStorage storage $ = compoundV3AdapterStorage();
        // Recipient pin: a recall may ONLY land in the adapter's own vault. The legit caller (the
        // StrategyManager) already passes the vault; this makes redirecting the position impossible.
        if (to != $._vault) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IProtocolAdapter.ProtocolAdapterInvalidRecipient(to);
        }
        address asset_ = $._asset;
        // Comet withdraws to the caller (this adapter); cap at our supplied balance, then forward.
        uint256 supplied = IComet($._comet).balanceOf(address(this));
        uint256 ask = amount > supplied ? supplied : amount;
        if (ask > 0) IComet($._comet).withdraw(asset_, ask);
        withdrawn = AdapterBaseLib.transferHonest(asset_, to, ask);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    function harvest() internal {
        _checkOperator();
        ReentrancyGuardLib.nonReentrantBefore();
        CompoundV3AdapterStorage storage $ = compoundV3AdapterStorage();
        address rewardsCtl = $._cometRewards;
        if (rewardsCtl == address(0)) {
            ReentrancyGuardLib.nonReentrantAfter();
            return;
        }
        (address rewardToken,,) = ICometRewards(rewardsCtl).rewardConfig($._comet);
        ICometRewards(rewardsCtl).claimTo($._comet, address(this), address(this), true);
        if (rewardToken != address(0)) {
            uint256 forwarded = AdapterBaseLib.forwardRewardRaw(rewardToken, $._rewardRecipient);
            if (forwarded > 0) emit IProtocolAdapter.RewardsForwarded(rewardToken, $._rewardRecipient, forwarded);
        }
        ReentrancyGuardLib.nonReentrantAfter();
    }

    function emergencyWithdraw() internal returns (uint256 recovered) {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ReentrancyGuardLib.nonReentrantBefore();
        CompoundV3AdapterStorage storage $ = compoundV3AdapterStorage();
        address asset_ = $._asset;
        uint256 supplied = IComet($._comet).balanceOf(address(this));
        if (supplied > 0) IComet($._comet).withdraw(asset_, supplied);
        recovered = AdapterBaseLib.transferHonest(asset_, $._vault, AdapterBaseLib.balanceOfSelf(asset_));
        emit IProtocolAdapter.EmergencyWithdrawn(asset_, $._vault, recovered);
        ReentrancyGuardLib.nonReentrantAfter();
    }
}
