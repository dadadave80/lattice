// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {AdapterBaseLib} from "@lattice/defi/libraries/AdapterBaseLib.sol";
import {ICurveStableSwapAdapter} from "@lattice/interfaces/defi/ICurveStableSwapAdapter.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {ICurveGauge} from "@lattice/interfaces/external/curve/ICurveGauge.sol";
import {ICurveStableSwapPool} from "@lattice/interfaces/external/curve/ICurveStableSwapPool.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.CurveStableSwapAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
/// Precomputed: 0x9a875cb7e904ab3576fe7e6b7405b28b9f810acb5bf4def0fec57c5e754def00
bytes32 constant CURVE_STABLE_SWAP_ADAPTER_STORAGE_SLOT =
    0x9a875cb7e904ab3576fe7e6b7405b28b9f810acb5bf4def0fec57c5e754def00;

/// @dev ERC-165 storage location (shared across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant CURVE_STABLE_SWAP_ADAPTER_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x8f7783e6 is `type(IProtocolAdapter).interfaceId` (same value the Aave/Compound/ERC4626
/// adapters register; the ERC-165 map slot is shared because the interface ID is identical).
/// `keccak256(abi.encode(bytes4(0x8f7783e6), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IPROTOCOLADAPTER_SLOT = 0x789387b95720f4aa713e912bc377a2f999f1310b69003727d9c01b7ea1494c77;

/// @dev 0xfa38ccb7 is `type(ICurveStableSwapAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xfa38ccb7), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ICURVESTABLESWAPADAPTER_SLOT =
    0x5d7c390f2f6bf0ca6f51b6ea0940c100b21726e3e202811c94c2ff39040d4299;

/// @dev Basis-point denominator for the slippage tolerance.
uint256 constant CURVE_BPS_DENOMINATOR = 10_000;

/// @notice ERC-7201 namespaced storage for the Curve StableSwap single-sided LP adapter.
/// @custom:storage-location erc7201:lattice.storage.CurveStableSwapAdapter
struct CurveStableSwapAdapterStorage {
    /// @dev The Curve StableSwap pool (2-coin) this adapter LPs into.
    address _pool;
    /// @dev The pool's LP token (held loose or staked in the gauge).
    address _lpToken;
    /// @dev Optional staking gauge; address(0) means the adapter holds LP unstaked.
    address _gauge;
    /// @dev The underlying asset supplied/withdrawn single-sided (== pool coin at `_coinIndex`).
    address _asset;
    /// @dev The Lattice vault funds are returned to on withdraw/emergency.
    address _vault;
    /// @dev Reward recipient for raw-forwarded CRV (+ gauge extras).
    address _rewardRecipient;
    /// @dev The CRV (primary gauge reward) token forwarded raw on harvest; address(0) == none.
    address _crvToken;
    /// @dev The pool coin index `_asset` occupies (0 or 1 for a 2-coin pool).
    int128 _coinIndex;
    /// @dev Slippage tolerance in basis points applied to add/remove min-out floors.
    uint256 _slippageBps;
    /// @dev Authorized operator: the SOLE caller permitted to invoke `deploy`/`withdraw`/`harvest`
    ///      (the StrategyManager in the live system). Zero until wired ⇒ that trio reverts.
    ///      APPENDED last (append-only ERC-7201 rule — never reorder/insert).
    address _operator;
}

/// @title CurveStableSwapAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Curve (https://github.com/curvefi/curve-contract)
/// @notice Logic for a single-asset, single-sided Curve StableSwap LP strategy. Deposits the
///         configured `asset` into one side of a 2-coin pool, holds (or stakes) the LP, and values
///         the position in `asset` units via `get_virtual_price`. Reentrancy-gated,
///         pause/emergency-aware, shortfall-honest. CRV/extra rewards forwarded RAW (no swap) and
///         NOT counted in NAV.
/// @dev Pool shape is pinned to **N == 2** by `ICurveStableSwapPool` (Curve pools are generated
///      per-N; the coins array is fixed-size). The adapter supplies one side via `_coinIndex` and
///      leaves the other at zero.
library CurveStableSwapAdapterLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function curveStableSwapAdapterStorage() internal pure returns (CurveStableSwapAdapterStorage storage $) {
        assembly {
            $.slot := CURVE_STABLE_SWAP_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    function __CurveStableSwapAdapter_init(
        address pool_,
        address lpToken_,
        address gauge_,
        address asset_,
        int128 coinIndex_,
        address vault_,
        address recipient_,
        uint256 slippageBps_
    ) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        // gauge_ may be address(0) (unstaked); everything else is required.
        if (
            pool_ == address(0) || lpToken_ == address(0) || asset_ == address(0) || vault_ == address(0)
                || recipient_ == address(0)
        ) {
            revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        }
        if (coinIndex_ != 0 && coinIndex_ != 1) {
            revert ICurveStableSwapAdapter.CurveStableSwapAdapterBadCoinIndex(coinIndex_);
        }
        if (slippageBps_ > CURVE_BPS_DENOMINATOR) {
            revert ICurveStableSwapAdapter.CurveStableSwapAdapterSlippageTooHigh(slippageBps_, CURVE_BPS_DENOMINATOR);
        }
        // The pool's coin at `coinIndex_` must be the asset we supply/withdraw single-sided.
        address poolCoin = ICurveStableSwapPool(pool_).coins(uint256(int256(coinIndex_)));
        if (poolCoin != asset_) {
            revert ICurveStableSwapAdapter.CurveStableSwapAdapterAssetMismatch(poolCoin, asset_);
        }

        CurveStableSwapAdapterStorage storage $ = curveStableSwapAdapterStorage();
        $._pool = pool_;
        $._lpToken = lpToken_;
        $._gauge = gauge_;
        $._asset = asset_;
        $._vault = vault_;
        $._rewardRecipient = recipient_;
        $._coinIndex = coinIndex_;
        $._slippageBps = slippageBps_;

        registerInterface();
        emit ICurveStableSwapAdapter.CurveStableSwapAdapterConfigured(pool_, lpToken_, asset_, coinIndex_);
        if (gauge_ != address(0)) emit ICurveStableSwapAdapter.CurveGaugeSet(gauge_);
        emit ICurveStableSwapAdapter.CurveSlippageSet(slippageBps_);
        emit IProtocolAdapter.RewardRecipientSet(recipient_);
    }

    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IPROTOCOLADAPTER_SLOT, true)
            sstore(ERC165_MAP_ICURVESTABLESWAPADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  VIEWS
    //////////////////////////////////////////////////////////////////////////*//

    function asset() internal view returns (address) {
        return curveStableSwapAdapterStorage()._asset;
    }

    function vault() internal view returns (address) {
        return curveStableSwapAdapterStorage()._vault;
    }

    function pool() internal view returns (address) {
        return curveStableSwapAdapterStorage()._pool;
    }

    function lpToken() internal view returns (address) {
        return curveStableSwapAdapterStorage()._lpToken;
    }

    function gauge() internal view returns (address) {
        return curveStableSwapAdapterStorage()._gauge;
    }

    function crvToken() internal view returns (address) {
        return curveStableSwapAdapterStorage()._crvToken;
    }

    function coinIndex() internal view returns (int128) {
        return curveStableSwapAdapterStorage()._coinIndex;
    }

    function slippageBps() internal view returns (uint256) {
        return curveStableSwapAdapterStorage()._slippageBps;
    }

    function rewardRecipient() internal view returns (address) {
        return curveStableSwapAdapterStorage()._rewardRecipient;
    }

    function operator() internal view returns (address) {
        return curveStableSwapAdapterStorage()._operator;
    }

    /// @dev Reverts `ProtocolAdapterUnauthorized` unless the caller is the wired operator. Placed at
    ///      the very top of `deploy`/`withdraw`/`harvest` — BEFORE the reentrancy guard — so an
    ///      unauthorized call never leaves the guard latched. Zero operator ⇒ always reverts.
    function _checkOperator() private view {
        if (msg.sender != curveStableSwapAdapterStorage()._operator) {
            revert IProtocolAdapter.ProtocolAdapterUnauthorized(msg.sender);
        }
    }

    function minHealthFactor() internal pure returns (uint256) {
        return type(uint256).max; // LP-only, no debt
    }

    function healthFactor() internal pure returns (uint256) {
        return type(uint256).max; // no debt
    }

    function isPaused() internal view returns (bool) {
        return PausableLib.paused() || EmergencyStopLib.isStopped();
    }

    /// @notice Total LP controlled by this adapter = staked-in-gauge + held loose.
    /// @dev Counts both so that LP acquired before a gauge was wired (or left loose) is never
    ///      undercounted in valuation.
    function _lpHeld(CurveStableSwapAdapterStorage storage $) private view returns (uint256) {
        uint256 loose = AdapterBaseLib.balanceOfSelf($._lpToken);
        address g = $._gauge;
        if (g != address(0)) return loose + ICurveGauge(g).balanceOf(address(this));
        return loose;
    }

    /// @notice Position value in `asset` units = lpHeld * get_virtual_price() / 1e18.
    /// @dev **Read-only reentrancy:** `get_virtual_price()` is read-only-reentrancy-exposed on real
    ///      Curve pools (its value can be skewed mid-callback). This adapter never reads it inside a
    ///      foreign external interaction it does not control: `deploy`/`withdraw`/`emergencyWithdraw`
    ///      are all `nonReentrant`, and VaultCore/StrategyManager block share-price-sensitive vault
    ///      entries while a rebalance is in flight (they consult `reentrancyGuardEntered`). This view
    ///      is therefore only consumed outside the adapter's own state-changing calls, so we do NOT
    ///      add a self-reentrant valuation. `get_virtual_price` is monotone non-decreasing as the
    ///      pool earns fees, so `lp * vp / 1e18` is a safe lower bound on the single-coin redeemable
    ///      value of an over-collateralized stable pool.
    /// @dev **Idle leg (NAV-gap fix):** adds the adapter's idle underlying-asset balance to the
    ///      LP-valued position. `IVaultCore.allocateToStrategy` pushes funds here with a bare transfer
    ///      that does NOT add liquidity, so undeployed funds sit idle until `deploy()` (and `lp` can
    ///      be 0 while idle is non-zero — exactly the allocate-before-deploy state). Counting that
    ///      idle keeps the vault's share price flat across the allocate→deploy window. No
    ///      double-count: the idle is in neither the vault's idle nor the LP position, and after
    ///      `deploy()` idle→~0 while LP grows by the same value, so the sum is invariant across
    ///      deploy. The idle asset is held loose by the adapter (not in the pool), so reading it is
    ///      free of the `get_virtual_price` read-only-reentrancy concern.
    function totalAssetsManaged() internal view returns (uint256) {
        CurveStableSwapAdapterStorage storage $ = curveStableSwapAdapterStorage();
        uint256 idle = AdapterBaseLib.balanceOfSelf($._asset);
        uint256 lp = _lpHeld($);
        if (lp == 0) return idle;
        return ((lp * ICurveStableSwapPool($._pool).get_virtual_price()) / 1e18) + idle;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function setGauge(address gauge_) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        curveStableSwapAdapterStorage()._gauge = gauge_; // address(0) clears (run unstaked)
        emit ICurveStableSwapAdapter.CurveGaugeSet(gauge_);
    }

    function setCrvToken(address token) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        curveStableSwapAdapterStorage()._crvToken = token; // address(0) clears (skip forwarding)
    }

    function setSlippageBps(uint256 slippageBps_) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (slippageBps_ > CURVE_BPS_DENOMINATOR) {
            revert ICurveStableSwapAdapter.CurveStableSwapAdapterSlippageTooHigh(slippageBps_, CURVE_BPS_DENOMINATOR);
        }
        curveStableSwapAdapterStorage()._slippageBps = slippageBps_;
        emit ICurveStableSwapAdapter.CurveSlippageSet(slippageBps_);
    }

    function setRewardRecipient(address recipient) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (recipient == address(0)) revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        curveStableSwapAdapterStorage()._rewardRecipient = recipient;
        emit IProtocolAdapter.RewardRecipientSet(recipient);
    }

    /// @notice Sets the authorized operator for `deploy`/`withdraw`/`harvest` (admin-only). Rejects
    ///         `address(0)` so the trio cannot be opened to an unauthenticated default.
    function setOperator(address operator_) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (operator_ == address(0)) revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        curveStableSwapAdapterStorage()._operator = operator_;
        emit IProtocolAdapter.OperatorSet(operator_);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  LP LEG
    //////////////////////////////////////////////////////////////////////////*//

    function deploy() internal returns (uint256 deployed) {
        _checkOperator();
        ReentrancyGuardLib.nonReentrantBefore();
        if (isPaused()) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IProtocolAdapter.ProtocolAdapterPaused();
        }
        CurveStableSwapAdapterStorage storage $ = curveStableSwapAdapterStorage();
        address asset_ = $._asset;
        uint256 idle = AdapterBaseLib.balanceOfSelf(asset_);
        if (idle == 0) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IProtocolAdapter.ProtocolAdapterNothingToDeploy();
        }

        address pool_ = $._pool;
        int128 idx = $._coinIndex;
        uint256[2] memory amounts;
        amounts[uint256(int256(idx))] = idle;

        // Slippage floor: expected LP from calc, haircut by slippageBps. `calc_token_amount` ignores
        // most pool fees, so the bps haircut absorbs fee + rounding.
        uint256 expectedLp = ICurveStableSwapPool(pool_).calc_token_amount(amounts, true);
        uint256 minMint = (expectedLp * (CURVE_BPS_DENOMINATOR - $._slippageBps)) / CURVE_BPS_DENOMINATOR;

        AdapterBaseLib.forceApprove(asset_, pool_, idle);
        uint256 minted = ICurveStableSwapPool(pool_).add_liquidity(amounts, minMint);

        // Stake freshly minted LP if a gauge is configured.
        address g = $._gauge;
        if (g != address(0) && minted > 0) {
            AdapterBaseLib.forceApprove($._lpToken, g, minted);
            ICurveGauge(g).deposit(minted);
        }

        deployed = idle;
        emit IProtocolAdapter.Deployed(asset_, idle);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    function withdraw(uint256 amount, address to) internal returns (uint256 withdrawn) {
        _checkOperator();
        ReentrancyGuardLib.nonReentrantBefore();
        CurveStableSwapAdapterStorage storage $ = curveStableSwapAdapterStorage();
        // Recipient pin: a recall may ONLY land in the adapter's own vault. The legit caller (the
        // StrategyManager) already passes the vault; this makes redirecting the position impossible.
        if (to != $._vault) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IProtocolAdapter.ProtocolAdapterInvalidRecipient(to);
        }
        address asset_ = $._asset;
        address pool_ = $._pool;
        int128 idx = $._coinIndex;

        uint256 lp = _lpHeld($);
        if (lp == 0) {
            ReentrancyGuardLib.nonReentrantAfter();
            return 0;
        }

        // LP to burn for `amount` of asset. Inverse of valuation (`amount = lp * vp / 1e18`), capped
        // at LP held. Reading `get_virtual_price` here is safe: we are inside our own nonReentrant op
        // (no foreign callback can interpose before the subsequent remove), and VaultCore blocks
        // share-price-sensitive entries while this rebalance is in flight.
        uint256 vp = ICurveStableSwapPool(pool_).get_virtual_price();
        uint256 lpToBurn = (amount * 1e18) / vp;
        if (lpToBurn > lp) lpToBurn = lp;
        if (lpToBurn == 0) {
            ReentrancyGuardLib.nonReentrantAfter();
            return 0;
        }

        // Pull LP from the gauge first if staked.
        _ensureLooseLp($, lpToBurn);

        // Slippage floor for the single-coin exit.
        uint256 expectedOut = ICurveStableSwapPool(pool_).calc_withdraw_one_coin(lpToBurn, idx);
        uint256 minOut = (expectedOut * (CURVE_BPS_DENOMINATOR - $._slippageBps)) / CURVE_BPS_DENOMINATOR;

        // Measure the real asset delta the remove produces, then forward it honestly to `to`.
        uint256 beforeBal = AdapterBaseLib.balanceOfSelf(asset_);
        ICurveStableSwapPool(pool_).remove_liquidity_one_coin(lpToBurn, idx, minOut);
        uint256 received = AdapterBaseLib.balanceOfSelf(asset_) - beforeBal;

        withdrawn = AdapterBaseLib.transferHonest(asset_, to, received);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    function harvest() internal {
        _checkOperator();
        ReentrancyGuardLib.nonReentrantBefore();
        CurveStableSwapAdapterStorage storage $ = curveStableSwapAdapterStorage();
        address g = $._gauge;
        if (g == address(0)) {
            ReentrancyGuardLib.nonReentrantAfter();
            return; // unstaked: nothing to claim
        }
        // Claim CRV (+ any extra gauge rewards) to this adapter, then forward the configured CRV
        // token raw. Extra reward tokens beyond CRV are out of scope of the minimal vendored surface;
        // an integrator that needs them sweeps via a separate path.
        ICurveGauge(g).claim_rewards(address(this));

        address crv = $._crvToken;
        if (crv != address(0)) {
            uint256 forwarded = AdapterBaseLib.forwardRewardRaw(crv, $._rewardRecipient);
            if (forwarded > 0) emit IProtocolAdapter.RewardsForwarded(crv, $._rewardRecipient, forwarded);
        }
        ReentrancyGuardLib.nonReentrantAfter();
    }

    function emergencyWithdraw() internal returns (uint256 recovered) {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ReentrancyGuardLib.nonReentrantBefore();
        CurveStableSwapAdapterStorage storage $ = curveStableSwapAdapterStorage();
        address asset_ = $._asset;
        address pool_ = $._pool;
        int128 idx = $._coinIndex;

        // Unstake everything, then remove all liquidity single-coin. minOut == 0: an emergency exit
        // prioritizes getting funds out over slippage protection (admin-gated, runs even when stopped).
        uint256 lp = _lpHeld($);
        if (lp > 0) {
            _ensureLooseLp($, lp);
            uint256 loose = AdapterBaseLib.balanceOfSelf($._lpToken);
            if (loose > 0) ICurveStableSwapPool(pool_).remove_liquidity_one_coin(loose, idx, 0);
        }
        recovered = AdapterBaseLib.transferHonest(asset_, $._vault, AdapterBaseLib.balanceOfSelf(asset_));
        emit IProtocolAdapter.EmergencyWithdrawn(asset_, $._vault, recovered);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Ensures at least `need` LP is held loose, unstaking the shortfall from the gauge.
    function _ensureLooseLp(CurveStableSwapAdapterStorage storage $, uint256 need) private {
        uint256 loose = AdapterBaseLib.balanceOfSelf($._lpToken);
        if (loose >= need) return;
        address g = $._gauge;
        if (g == address(0)) return; // nothing staked; caller burns what's loose
        uint256 short = need - loose;
        uint256 staked = ICurveGauge(g).balanceOf(address(this));
        uint256 pull = short > staked ? staked : short;
        if (pull > 0) ICurveGauge(g).withdraw(pull);
    }
}
