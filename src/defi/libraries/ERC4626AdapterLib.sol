// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {AdapterBaseLib} from "@lattice/defi/libraries/AdapterBaseLib.sol";
import {IERC4626Adapter} from "@lattice/interfaces/defi/IERC4626Adapter.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC4626Adapter")) - 1)) & ~bytes32(uint256(0xff))`.
/// Precomputed: 0x8e54862d9117c02647004a257ec52ba4f4c6ce02a01e23235ed8d34a2127c500
bytes32 constant ERC4626_ADAPTER_STORAGE_SLOT = 0x8e54862d9117c02647004a257ec52ba4f4c6ce02a01e23235ed8d34a2127c500;

/// @dev ERC-165 storage location (shared across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC4626_ADAPTER_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x8f7783e6 is `type(IProtocolAdapter).interfaceId` (same value the Aave/Compound adapters
/// register; the ERC-165 map slot is shared because the interface ID is identical).
/// `keccak256(abi.encode(bytes4(0x8f7783e6), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IPROTOCOLADAPTER_SLOT = 0x789387b95720f4aa713e912bc377a2f999f1310b69003727d9c01b7ea1494c77;

/// @dev 0x6189942b is `type(IERC4626Adapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x6189942b), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC4626ADAPTER_SLOT = 0x84ec7ed953664aca1f16de58454031d5ee56bdfdc133c3183893a830a7b1c08b;

/// @notice ERC-7201 namespaced storage for the ERC4626-wrap adapter.
/// @custom:storage-location erc7201:lattice.storage.ERC4626Adapter
struct ERC4626AdapterStorage {
    /// @dev The target ERC4626 vault (Yearn v3 / MetaMorpho / any ERC4626) deposited into.
    address _targetVault;
    /// @dev The underlying asset (== target vault's `asset()` == Lattice vault asset).
    address _asset;
    /// @dev The Lattice vault funds are returned to on withdraw/emergency.
    address _vault;
    /// @dev Reward recipient for the optional raw-forwarded side token.
    address _rewardRecipient;
    /// @dev Optional side-reward token forwarded raw on `harvest()`; address(0) if none.
    address _sideRewardToken;
    /// @dev Authorized operator: the SOLE caller permitted to invoke `deploy`/`withdraw`/`harvest`
    ///      (the StrategyManager in the live system). Zero until wired ⇒ that trio reverts.
    ///      APPENDED last (append-only ERC-7201 rule — never reorder/insert).
    address _operator;
}

/// @title ERC4626AdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Logic wrapping any ERC4626 vault (Yearn v3 / MetaMorpho) as a Lattice strategy.
///         NAV via `convertToAssets` (no oracle). Supply-only.
library ERC4626AdapterLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function erc4626AdapterStorage() internal pure returns (ERC4626AdapterStorage storage $) {
        assembly {
            $.slot := ERC4626_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    function __ERC4626Adapter_init(address target, address asset_, address vault_, address recipient_) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        if (target == address(0) || asset_ == address(0) || vault_ == address(0) || recipient_ == address(0)) {
            revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        }
        address targetAsset = IERC4626(target).asset();
        if (targetAsset != asset_) revert IERC4626Adapter.ERC4626AdapterAssetMismatch(targetAsset, asset_);

        ERC4626AdapterStorage storage $ = erc4626AdapterStorage();
        $._targetVault = target;
        $._asset = asset_;
        $._vault = vault_;
        $._rewardRecipient = recipient_;

        registerInterface();
        emit IERC4626Adapter.ERC4626AdapterConfigured(target, asset_, vault_);
        emit IProtocolAdapter.RewardRecipientSet(recipient_);
    }

    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IPROTOCOLADAPTER_SLOT, true)
            sstore(ERC165_MAP_IERC4626ADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  VIEWS
    //////////////////////////////////////////////////////////////////////////*//

    function asset() internal view returns (address) {
        return erc4626AdapterStorage()._asset;
    }

    function vault() internal view returns (address) {
        return erc4626AdapterStorage()._vault;
    }

    function targetVault() internal view returns (address) {
        return erc4626AdapterStorage()._targetVault;
    }

    function sideRewardToken() internal view returns (address) {
        return erc4626AdapterStorage()._sideRewardToken;
    }

    function rewardRecipient() internal view returns (address) {
        return erc4626AdapterStorage()._rewardRecipient;
    }

    function operator() internal view returns (address) {
        return erc4626AdapterStorage()._operator;
    }

    /// @dev Reverts `ProtocolAdapterUnauthorized` unless the caller is the wired operator. Placed at
    ///      the very top of `deploy`/`withdraw`/`harvest` — BEFORE the reentrancy guard — so an
    ///      unauthorized call never leaves the guard latched. Zero operator ⇒ always reverts.
    function _checkOperator() private view {
        if (msg.sender != erc4626AdapterStorage()._operator) {
            revert IProtocolAdapter.ProtocolAdapterUnauthorized(msg.sender);
        }
    }

    function healthFactor() internal pure returns (uint256) {
        return type(uint256).max; // no debt
    }

    function minHealthFactor() internal pure returns (uint256) {
        return type(uint256).max; // supply-only
    }

    function isPaused() internal view returns (bool) {
        return PausableLib.paused() || EmergencyStopLib.isStopped();
    }

    /// @notice NAV = convertToAssets(shareBalance) + idle underlying. No oracle — ERC4626 1:1.
    /// @dev **Idle leg (NAV-gap fix):** adds the adapter's idle underlying balance to the
    ///      share-priced position. `IVaultCore.allocateToStrategy` pushes funds here with a bare
    ///      transfer that does NOT deposit into the target vault, so undeployed funds sit idle until
    ///      `deploy()` (and `shares` can be 0 while idle is non-zero — exactly the allocate-before-
    ///      deploy state). Counting that idle keeps the vault's share price flat across the
    ///      allocate→deploy window. No double-count: the idle is in neither the vault's idle nor the
    ///      target shares, and after `deploy()` idle→~0 while shares grow by the same value, so the
    ///      sum is invariant across deploy.
    function totalAssetsManaged() internal view returns (uint256) {
        ERC4626AdapterStorage storage $ = erc4626AdapterStorage();
        uint256 idle = AdapterBaseLib.balanceOfSelf($._asset);
        uint256 shares = IERC4626($._targetVault).balanceOf(address(this));
        if (shares == 0) return idle;
        return IERC4626($._targetVault).convertToAssets(shares) + idle;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function setSideRewardToken(address token) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        erc4626AdapterStorage()._sideRewardToken = token; // address(0) clears
    }

    function setRewardRecipient(address recipient) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (recipient == address(0)) revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        erc4626AdapterStorage()._rewardRecipient = recipient;
        emit IProtocolAdapter.RewardRecipientSet(recipient);
    }

    /// @notice Sets the authorized operator for `deploy`/`withdraw`/`harvest` (admin-only). Rejects
    ///         `address(0)` so the trio cannot be opened to an unauthenticated default.
    function setOperator(address operator_) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (operator_ == address(0)) revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        erc4626AdapterStorage()._operator = operator_;
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
        ERC4626AdapterStorage storage $ = erc4626AdapterStorage();
        address asset_ = $._asset;
        uint256 idle = AdapterBaseLib.balanceOfSelf(asset_);
        if (idle == 0) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IProtocolAdapter.ProtocolAdapterNothingToDeploy();
        }
        AdapterBaseLib.forceApprove(asset_, $._targetVault, idle);
        IERC4626($._targetVault).deposit(idle, address(this));
        deployed = idle;
        emit IProtocolAdapter.Deployed(asset_, idle);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    function withdraw(uint256 amount, address to) internal returns (uint256 withdrawn) {
        _checkOperator();
        ReentrancyGuardLib.nonReentrantBefore();
        ERC4626AdapterStorage storage $ = erc4626AdapterStorage();
        // Recipient pin: a recall may ONLY land in the adapter's own vault. The legit caller (the
        // StrategyManager) already passes the vault; this makes redirecting the position impossible.
        if (to != $._vault) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IProtocolAdapter.ProtocolAdapterInvalidRecipient(to);
        }
        IERC4626 t = IERC4626($._targetVault);
        // Shares needed for `amount` assets, capped at our share balance and the vault's maxRedeem.
        uint256 ourShares = t.balanceOf(address(this));
        uint256 wantShares = t.convertToShares(amount);
        uint256 redeemable = t.maxRedeem(address(this));
        uint256 shares = wantShares > ourShares ? ourShares : wantShares;
        if (shares > redeemable) shares = redeemable;
        if (shares > 0) {
            withdrawn = t.redeem(shares, to, address(this));
        }
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Forwards an optional side-reward token raw. Most ERC4626 vaults auto-compound, so
    ///         this is usually a no-op. Never reverts the withdraw path.
    function harvest() internal {
        _checkOperator();
        ReentrancyGuardLib.nonReentrantBefore();
        ERC4626AdapterStorage storage $ = erc4626AdapterStorage();
        address side = $._sideRewardToken;
        if (side != address(0)) {
            uint256 forwarded = AdapterBaseLib.forwardRewardRaw(side, $._rewardRecipient);
            if (forwarded > 0) emit IProtocolAdapter.RewardsForwarded(side, $._rewardRecipient, forwarded);
        }
        ReentrancyGuardLib.nonReentrantAfter();
    }

    function emergencyWithdraw() internal returns (uint256 recovered) {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ReentrancyGuardLib.nonReentrantBefore();
        ERC4626AdapterStorage storage $ = erc4626AdapterStorage();
        IERC4626 t = IERC4626($._targetVault);
        uint256 shares = t.balanceOf(address(this));
        uint256 redeemable = t.maxRedeem(address(this));
        if (shares > redeemable) shares = redeemable;
        if (shares > 0) {
            recovered = t.redeem(shares, $._vault, address(this));
        }
        emit IProtocolAdapter.EmergencyWithdrawn($._asset, $._vault, recovered);
        ReentrancyGuardLib.nonReentrantAfter();
    }
}
