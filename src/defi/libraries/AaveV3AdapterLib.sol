// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {AdapterBaseLib} from "@lattice/defi/libraries/AdapterBaseLib.sol";
import {IAaveV3Adapter} from "@lattice/interfaces/IAaveV3Adapter.sol";
import {IERC20} from "@lattice/interfaces/IERC20.sol";
import {IProtocolAdapter} from "@lattice/interfaces/IProtocolAdapter.sol";
import {IAToken} from "@lattice/interfaces/external/IAToken.sol";
import {IAaveV3Pool} from "@lattice/interfaces/external/IAaveV3Pool.sol";
import {IPoolAddressesProvider} from "@lattice/interfaces/external/IPoolAddressesProvider.sol";
import {ChainlinkAdapterLib} from "@lattice/oracles/libraries/ChainlinkAdapterLib.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.AaveV3Adapter")) - 1)) & ~bytes32(uint256(0xff))`.
/// Precomputed: 0x78e1f0849c8352c9588d407dc28e9981715ac638a0aa753fc1ecf5191c1f8200
bytes32 constant AAVE_V3_ADAPTER_STORAGE_SLOT = 0x78e1f0849c8352c9588d407dc28e9981715ac638a0aa753fc1ecf5191c1f8200;

/// @dev ERC-165 storage location (shared across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant AAVE_V3_ADAPTER_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x8f7783e6 is `type(IProtocolAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x8f7783e6), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IPROTOCOLADAPTER_SLOT = 0x789387b95720f4aa713e912bc377a2f999f1310b69003727d9c01b7ea1494c77;

/// @dev 0x358066bd is `type(IAaveV3Adapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x358066bd), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IAAVEV3ADAPTER_SLOT = 0xe468d72a593ceecc9e0a362a31920ed641375c6a53da65d4526c31d16027629c;

/// @dev Aave variable interest-rate mode (1 == stable, deprecated; 2 == variable).
uint256 constant AAVE_VARIABLE_RATE = 2;

/// @notice ERC-7201 namespaced storage for the Aave v3 adapter.
/// @custom:storage-location erc7201:lattice.storage.AaveV3Adapter
struct AaveV3AdapterStorage {
    /// @dev Aave PoolAddressesProvider; the Pool is re-resolved from this on every call.
    address _provider;
    /// @dev The underlying asset this adapter supplies/borrows (== vault asset).
    address _asset;
    /// @dev The vault funds are returned to on withdraw/emergency.
    address _vault;
    /// @dev Reward recipient for raw-forwarded incentive tokens.
    address _rewardRecipient;
    /// @dev Chainlink feed key (in the Lattice ChainlinkAdapter) pricing the asset in USD (WAD).
    ///      Only consumed by the leverage valuation path.
    bytes32 _assetUsdFeedKey;
    /// @dev Minimum health factor (WAD). Lever/deploy must not push HF below this.
    uint256 _minHealthFactorWad;
    /// @dev Current eMode category set on the Pool (cached for views).
    uint8 _eModeCategory;
}

/// @title AaveV3AdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice All logic for the Aave v3 adapter facet. Supply leg values 1:1 via aToken.balanceOf;
///         leverage leg values net equity via the Lattice oracle (Task 8). Reentrancy-gated,
///         pause/emergency-aware, shortfall-honest.
library AaveV3AdapterLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function aaveV3AdapterStorage() internal pure returns (AaveV3AdapterStorage storage $) {
        assembly {
            $.slot := AAVE_V3_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the Aave adapter. Must run inside a pre/postInitializer block, after
    ///         AccessControl is initialized.
    /// @param provider          Aave PoolAddressesProvider.
    /// @param asset_            Underlying asset (must equal the vault's asset).
    /// @param vault_            Vault to return funds to.
    /// @param rewardRecipient_  Recipient for raw-forwarded rewards.
    /// @param assetUsdFeedKey   ChainlinkAdapter feed key for asset/USD (leverage valuation).
    /// @param minHealthFactorWad Initial HF floor (>= 1e18).
    function __AaveV3Adapter_init(
        address provider,
        address asset_,
        address vault_,
        address rewardRecipient_,
        bytes32 assetUsdFeedKey,
        uint256 minHealthFactorWad
    ) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);

        if (provider == address(0) || asset_ == address(0) || vault_ == address(0) || rewardRecipient_ == address(0)) {
            revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        }
        if (minHealthFactorWad < 1e18) {
            revert IAaveV3Adapter.AaveV3AdapterInvalidMinHealthFactor(minHealthFactorWad);
        }
        // Verify the asset is actually listed (has an aToken) on the resolved Pool.
        address pool = IPoolAddressesProvider(provider).getPool();
        if (IAaveV3Pool(pool).getReserveData(asset_).aTokenAddress == address(0)) {
            revert IAaveV3Adapter.AaveV3AdapterReserveNotListed(asset_);
        }

        AaveV3AdapterStorage storage $ = aaveV3AdapterStorage();
        $._provider = provider;
        $._asset = asset_;
        $._vault = vault_;
        $._rewardRecipient = rewardRecipient_;
        $._assetUsdFeedKey = assetUsdFeedKey;
        $._minHealthFactorWad = minHealthFactorWad;

        registerInterface();
        emit IAaveV3Adapter.AaveV3AdapterConfigured(provider, asset_, vault_);
        emit IProtocolAdapter.RewardRecipientSet(rewardRecipient_);
        emit IAaveV3Adapter.MinHealthFactorSet(minHealthFactorWad);
    }

    /// @notice Registers IProtocolAdapter + IAaveV3Adapter for ERC-165 discovery.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IPROTOCOLADAPTER_SLOT, true)
            sstore(ERC165_MAP_IAAVEV3ADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INTERNAL RESOLUTION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Re-resolves the live Pool from the provider on every call (picks up proxy upgrades).
    function _pool() internal view returns (IAaveV3Pool) {
        return IAaveV3Pool(IPoolAddressesProvider(aaveV3AdapterStorage()._provider).getPool());
    }

    /// @notice Resolves the live aToken for the configured asset.
    function aToken() internal view returns (address) {
        return _pool().getReserveData(aaveV3AdapterStorage()._asset).aTokenAddress;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    function asset() internal view returns (address) {
        return aaveV3AdapterStorage()._asset;
    }

    function vault() internal view returns (address) {
        return aaveV3AdapterStorage()._vault;
    }

    function addressesProvider() internal view returns (address) {
        return aaveV3AdapterStorage()._provider;
    }

    function rewardRecipient() internal view returns (address) {
        return aaveV3AdapterStorage()._rewardRecipient;
    }

    function eModeCategory() internal view returns (uint8) {
        return aaveV3AdapterStorage()._eModeCategory;
    }

    function minHealthFactor() internal view returns (uint256) {
        return aaveV3AdapterStorage()._minHealthFactorWad;
    }

    /// @notice True when the adapter is paused or emergency-stopped. `deploy()` checks this so a
    ///         paused adapter cannot brick the manager's `rebalance()` (it reverts, the manager's
    ///         pass-2 allocation having already pushed the bare transfer — funds sit idle, safe).
    function isPaused() internal view returns (bool) {
        return PausableLib.paused() || EmergencyStopLib.isStopped();
    }

    /// @notice Current health factor (WAD). Aave returns type(uint256).max when there is no debt.
    function healthFactor() internal view returns (uint256) {
        (,,,,, uint256 hf) = _pool().getUserAccountData(address(this));
        return hf;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          CONFIG (state-changing)
    //////////////////////////////////////////////////////////////////////////*//

    function setEMode(uint8 categoryId) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _pool().setUserEMode(categoryId);
        aaveV3AdapterStorage()._eModeCategory = categoryId;
        emit IAaveV3Adapter.EModeSet(categoryId);
    }

    function setMinHealthFactor(uint256 minHealthFactorWad) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (minHealthFactorWad < 1e18) {
            revert IAaveV3Adapter.AaveV3AdapterInvalidMinHealthFactor(minHealthFactorWad);
        }
        aaveV3AdapterStorage()._minHealthFactorWad = minHealthFactorWad;
        emit IAaveV3Adapter.MinHealthFactorSet(minHealthFactorWad);
    }

    function setRewardRecipient(address recipient) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (recipient == address(0)) revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        aaveV3AdapterStorage()._rewardRecipient = recipient;
        emit IProtocolAdapter.RewardRecipientSet(recipient);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          SUPPLY LEG (state-changing)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sweeps the adapter's idle asset balance into Aave via `Pool.supply`.
    /// @dev Reentrancy-gated. Reverts if paused/stopped or if there is nothing to deploy. Uses
    ///      exact-amount `forceApprove` to the freshly-resolved Pool (never infinite).
    function deploy() internal returns (uint256 deployed) {
        ReentrancyGuardLib.nonReentrantBefore();
        if (isPaused()) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IProtocolAdapter.ProtocolAdapterPaused();
        }
        AaveV3AdapterStorage storage $ = aaveV3AdapterStorage();
        address asset_ = $._asset;
        uint256 idle = AdapterBaseLib.balanceOfSelf(asset_);
        if (idle == 0) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IProtocolAdapter.ProtocolAdapterNothingToDeploy();
        }
        IAaveV3Pool pool = _pool();
        AdapterBaseLib.forceApprove(asset_, address(pool), idle);
        pool.supply(asset_, idle, address(this), 0);
        deployed = idle;
        emit IProtocolAdapter.Deployed(asset_, idle);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Withdraws up to `amount` of the asset from Aave to `to`, returning the REAL amount.
    /// @dev Reentrancy-gated. Calls `Pool.withdraw` (which itself caps at available collateral),
    ///      then honestly reports the balance delta to `to`. Allows shortfall (partial
    ///      liquidation / insufficient liquidity) — the StrategyManager raises
    ///      `StrategyManagerWithdrawShortfall` upstream if under-delivered.
    function withdraw(uint256 amount, address to) internal returns (uint256 withdrawn) {
        ReentrancyGuardLib.nonReentrantBefore();
        if (to == address(0)) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        }
        AaveV3AdapterStorage storage $ = aaveV3AdapterStorage();
        address asset_ = $._asset;
        // Aave sends the underlying directly to `to`; capture `to`'s delta to report honestly.
        uint256 beforeBal = IERC20(asset_).balanceOf(to);
        // Cap the request at the live aToken balance so we never ask for more than we hold.
        uint256 supplied = IAToken(aToken()).balanceOf(address(this));
        uint256 ask = amount > supplied ? supplied : amount;
        if (ask > 0) {
            _pool().withdraw(asset_, ask, to);
        }
        withdrawn = IERC20(asset_).balanceOf(to) - beforeBal;
        ReentrancyGuardLib.nonReentrantAfter();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              VALUATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Total assets managed (vault accounting / share price input).
    /// @dev Supply-only: the 1:1 aToken balance. When debt exists (leverage), Task 8 replaces
    ///      this with oracle-priced net equity. Rewards are NEVER counted here.
    function totalAssetsManaged() internal view returns (uint256) {
        AaveV3AdapterStorage storage $ = aaveV3AdapterStorage();
        (, uint256 totalDebtBase,,,,) = _pool().getUserAccountData(address(this));
        uint256 supplied = IAToken(aToken()).balanceOf(address(this));
        if (totalDebtBase == 0) {
            // No debt: 1:1 supply value, no oracle needed.
            return supplied;
        }
        // Debt present: net equity is computed by the leverage valuation (Task 8).
        return _netEquityAssets();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          LEVERAGE LEG (state-changing)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Borrows `borrowAmount` of the asset (variable rate) then re-supplies it, looping
    ///         leverage. Reverts if the resulting health factor would fall below the floor.
    function lever(uint256 borrowAmount) internal {
        ReentrancyGuardLib.nonReentrantBefore();
        if (isPaused()) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IProtocolAdapter.ProtocolAdapterPaused();
        }
        if (borrowAmount == 0) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IAaveV3Adapter.AaveV3AdapterZeroLeverAmount();
        }
        AaveV3AdapterStorage storage $ = aaveV3AdapterStorage();
        address asset_ = $._asset;
        IAaveV3Pool pool = _pool();

        // Borrow the asset to this adapter.
        pool.borrow(asset_, borrowAmount, AAVE_VARIABLE_RATE, 0, address(this));
        // Re-supply the borrowed asset as additional collateral.
        AdapterBaseLib.forceApprove(asset_, address(pool), borrowAmount);
        pool.supply(asset_, borrowAmount, address(this), 0);

        // Enforce the HF floor on the resulting position.
        _assertHealthFactorAboveFloor();

        emit IAaveV3Adapter.Levered(borrowAmount);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Withdraws `collateralToPull` of the asset from supply and repays that much debt,
    ///         decreasing leverage. Returns the amount of debt actually repaid.
    function delever(uint256 collateralToPull) internal returns (uint256 repaid) {
        ReentrancyGuardLib.nonReentrantBefore();
        AaveV3AdapterStorage storage $ = aaveV3AdapterStorage();
        address asset_ = $._asset;
        IAaveV3Pool pool = _pool();

        // Pull collateral to this adapter (Aave sends underlying here).
        uint256 pulled = pool.withdraw(asset_, collateralToPull, address(this));
        // Repay debt with the pulled collateral (capped at outstanding debt inside the Pool).
        AdapterBaseLib.forceApprove(asset_, address(pool), pulled);
        repaid = pool.repay(asset_, pulled, AAVE_VARIABLE_RATE, address(this));

        // Any over-pull beyond the debt stays as idle in the adapter; re-supply it to avoid drag.
        uint256 leftover = AdapterBaseLib.balanceOfSelf(asset_);
        if (leftover > 0) {
            AdapterBaseLib.forceApprove(asset_, address(pool), leftover);
            pool.supply(asset_, leftover, address(this), 0);
        }

        emit IAaveV3Adapter.Delevered(repaid);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @dev Reverts `ProtocolAdapterHealthFactorBreached` if the live HF is below the floor.
    function _assertHealthFactorAboveFloor() internal view {
        (,,,,, uint256 hf) = _pool().getUserAccountData(address(this));
        uint256 floor = aaveV3AdapterStorage()._minHealthFactorWad;
        if (hf < floor) {
            revert IProtocolAdapter.ProtocolAdapterHealthFactorBreached(hf, floor);
        }
    }

    /// @notice Oracle-priced net equity (collateral − debt) expressed in asset units (WAD-safe).
    /// @dev Aave reports collateral/debt in base ccy with 8 decimals. We convert the net base
    ///      amount to asset units using the Lattice oracle's asset/USD price (WAD), which enforces
    ///      staleness/positivity. NEVER reads spot. Single-asset looping: collateral and debt are
    ///      the same token, so the base→asset conversion divides by the same oracle price.
    function _netEquityAssets() internal view returns (uint256) {
        (uint256 collateralBase, uint256 debtBase,,,,) = _pool().getUserAccountData(address(this));
        if (collateralBase <= debtBase) return 0; // underwater => zero equity (honest)
        uint256 netBase8 = collateralBase - debtBase; // base ccy, 8 decimals

        // Oracle price asset/USD in WAD (reverts on stale/zero). Base ccy is USD (8 dp) on Aave.
        int256 priceWad = ChainlinkAdapterLib.latestAnswer(aaveV3AdapterStorage()._assetUsdFeedKey);
        // priceWad > 0 guaranteed by ChainlinkAdapterLib (reverts otherwise).
        uint256 price = uint256(priceWad);

        // netBase8 is USD * 1e8. Convert to asset units:
        //   netUsdWad = netBase8 * 1e10               (USD in WAD)
        //   assetWad  = netUsdWad * 1e18 / priceWad    (asset amount in WAD)
        //   assetUnits = assetWad / 1e(18 - assetDecimals)
        // Combine and scale to the asset's own decimals.
        uint8 assetDec = IERC20(aaveV3AdapterStorage()._asset).decimals();
        // assetUnits = netBase8 * 1e10 * 1e18 / price / 1e(18-assetDec)
        //            = netBase8 * 1e10 * 10^assetDec / price
        uint256 numerator = netBase8 * 1e10 * (10 ** assetDec);
        return numerator / price;
    }

    // ---- Stubs filled in by later tasks (compile placeholders) ----

    /// @dev Claims + forwards rewards raw. Real body in Task 9.
    function harvest() internal {
        // Task 9 wires the rewards controller claim; supply-only path has nothing to claim.
    }

    /// @dev Full exit to vault. Real body in Task 10.
    function emergencyWithdraw() internal returns (uint256) {
        return 0; // replaced in a later task
    }
}
