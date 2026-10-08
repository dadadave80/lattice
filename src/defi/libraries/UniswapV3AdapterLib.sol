// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {AdapterBaseLib} from "@lattice/defi/libraries/AdapterBaseLib.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {IUniswapV3Adapter} from "@lattice/interfaces/defi/IUniswapV3Adapter.sol";
import {INonfungiblePositionManager} from "@lattice/interfaces/external/uniswap/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "@lattice/interfaces/external/uniswap/IUniswapV3Pool.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {UniswapV3FullRangeMath} from "@lattice/utils/libraries/UniswapV3FullRangeMath.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.UniswapV3Adapter")) - 1)) & ~bytes32(uint256(0xff))`.
/// Precomputed: 0x6f3c1f877b0bf340477364a294f77f49bff3a5479f70012a0fb5cb2803b61e00
bytes32 constant UNISWAP_V3_ADAPTER_STORAGE_SLOT = 0x6f3c1f877b0bf340477364a294f77f49bff3a5479f70012a0fb5cb2803b61e00;

/// @dev ERC-165 storage location (shared across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant UNISWAP_V3_ADAPTER_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x8f7783e6 is `type(IProtocolAdapter).interfaceId` (same value the Aave/Compound/Curve/Lido
/// adapters register; the ERC-165 map slot is shared because the interface ID is identical).
/// `keccak256(abi.encode(bytes4(0x8f7783e6), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IPROTOCOLADAPTER_SLOT = 0x789387b95720f4aa713e912bc377a2f999f1310b69003727d9c01b7ea1494c77;

/// @dev 0xf723aa17 is `type(IUniswapV3Adapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xf723aa17), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IUNISWAPV3ADAPTER_SLOT = 0x18cf2bfdc937c75408cba5cf015af2a2f8d21a881c553ac382a288bcae5dc1c8;

/// @dev Basis-point denominator for the slippage tolerance.
uint256 constant UNISWAP_V3_BPS_DENOMINATOR = 10_000;

/// @notice ERC-7201 namespaced storage for the full-range Uniswap V3 LP adapter.
/// @custom:storage-location erc7201:lattice.storage.UniswapV3Adapter
struct UniswapV3AdapterStorage {
    /// @dev The Uniswap V3 NonfungiblePositionManager (custodies the position NFT).
    address _positionManager;
    /// @dev The Uniswap V3 pool this adapter LPs into.
    address _pool;
    /// @dev The pool's token0 (== the adapter's `asset`, the vault-facing accounting token).
    address _token0;
    /// @dev The pool's token1 (supplied by the keeper, never swapped).
    address _token1;
    /// @dev The Lattice vault funds are returned to on emergency exit.
    address _vault;
    /// @dev Reward recipient for collected fees (token0 + token1) and routed leftover token1.
    address _rewardRecipient;
    /// @dev The position NFT id; 0 means no position has been minted yet.
    uint256 _tokenId;
    /// @dev TWAP observation window (seconds) for `pool.observe`-based valuation.
    uint32 _twapWindow;
    /// @dev The pool fee tier (hundredths of a bip).
    uint24 _fee;
    /// @dev Full-range lower tick (min usable tick aligned to tickSpacing), cached at init.
    int24 _tickLower;
    /// @dev Full-range upper tick (max usable tick aligned to tickSpacing), cached at init.
    int24 _tickUpper;
    /// @dev Slippage tolerance in basis points applied to add/remove min-amount floors.
    uint256 _slippageBps;
    /// @dev Authorized operator: the SOLE caller permitted to invoke `deploy`/`withdraw`/`harvest`
    ///      (the StrategyManager in the live system). Zero until wired ⇒ that trio reverts.
    ///      APPENDED last (append-only ERC-7201 rule — never reorder/insert).
    address _operator;
}

/// @title UniswapV3AdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Uniswap V3 (https://github.com/Uniswap/v3-periphery)
/// @notice Logic for a **custom**, full-range Uniswap V3 LP strategy. A v3 LP is a two-token,
///         NFT-wrapped concentrated-liquidity position that does not fit the single-asset `IStrategy`
///         surface cleanly, so this adapter makes three deliberate simplifications: (1) the position
///         is pinned to **full-range** (min/max usable ticks) — no active range management; (2) the
///         adapter is **swap-free** — the keeper funds both token0 and token1; (3) the vault-facing
///         `asset` is **token0** and all NAV is denominated in token0.
///
///         **NAV is token0 only (#271).** Being swap-free, the adapter can only ever hand the vault
///         token0, and the vault counts only its asset. NAV is therefore idle token0 plus the position's
///         token0 leg. token1 is never NAV, whether it sits idle in the adapter (keeper-funded, or left
///         over from a deploy) or in the position's token1 leg. Counting it would put value in the share
///         price that no redeemer can receive.
///
///         **Valuation — TWAP, never spot (the central risk).** NAV reads the pool's TWAP via
///         `pool.observe(twapWindow)`, converts the arithmetic-mean tick to a sqrt price, and derives
///         the position's token0 leg at that price. It **never** reads `slot0`: the spot tick is
///         single-block manipulable (a flash swap can push it arbitrarily), and pricing vault shares off
///         spot would let an attacker mint/redeem at a skewed NAV. The TWAP averages the tick over the
///         whole window, so a one-block spike barely moves it. Uncollected fees are NOT counted in NAV
///         (they are the yield distribution, forwarded raw on `harvest`).
///
///         **Deploys happen at spot, so the guard bounds them.** The pool prices a mint or increase at spot,
///         while NAV counts the new token0 leg at the TWAP. A deploy therefore steps NAV by about
///         `consumed0 × (√(P_spot / P_twap) − 1)`, and `deploy` runs inside the permissionless `rebalance()`,
///         where anyone can move spot first. `deploy` refuses any step larger than `slippageBps` of the token0
///         it consumed (`UniswapV3AdapterDeployOffTwap`); the StrategyManager then reports the failed deploy and
///         the token0 stays idle and counted. Within the bound the step is real: an attacker choosing spot can
///         move NAV by up to `slippageBps` of each deploy, so keep `slippageBps` tight.
///
///         **Withdraw pays idle token0 only.** `withdraw(amount, to)` is token0-denominated and sends at
///         most the adapter's idle token0; it never removes liquidity. A decrease pays out at spot while
///         NAV counts the token0 leg at the TWAP, so with spot above the TWAP it frees less token0 than NAV
///         drops by, and the StrategyManager's value-loss check reverts the whole `rebalance()`; anyone
///         who can move spot could force that. Deciding from spot would make the recall manipulable, and
///         the token1 a decrease frees would sit idle with nothing to pair it. It returns the REAL token0
///         delta and never over-reports; anything beyond the idle token0 is an honest partial recall,
///         which the StrategyManager accepts.
///
///         **Exit needs the admin.** `rebalance()` can allocate into the position but never recall from it,
///         so capital allocated here reaches redeemers only after the admin's `emergencyWithdraw`; size the
///         target with that in mind. At a target of 0 a rebalance recalls the idle token0, the position's
///         token0 leg stays counted, and `removeStrategy` refuses the adapter. To retire it: set the target
///         to 0 and rebalance, then the admin calls `emergencyWithdraw`, which removes the position and sends
///         both tokens to the vault; then `removeStrategy`. The token0 replaces the token0 leg NAV already
///         counted, but the pool pays it at spot, so NAV steps by about `leg0 × (√(P_twap / P_spot) − 1)`
///         with no slippage floor: the admin should exit while spot sits near the TWAP (and through a private
///         transaction where one is available). The token1 lands in the vault outside NAV, and VaultCore has
///         no sweep for a non-asset token, so it stays there unless the vault's admin cuts one in.
/// @dev All heavy math lives in `UniswapV3FullRangeMath` to keep the facet under the 24KB limit.
library UniswapV3AdapterLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function uniswapV3AdapterStorage() internal pure returns (UniswapV3AdapterStorage storage $) {
        assembly {
            $.slot := UNISWAP_V3_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    function __UniswapV3Adapter_init(
        address positionManager_,
        address pool_,
        address vault_,
        address recipient_,
        uint32 twapWindow_,
        uint256 slippageBps_
    ) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        if (positionManager_ == address(0) || pool_ == address(0) || vault_ == address(0) || recipient_ == address(0)) {
            revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        }
        if (twapWindow_ == 0) revert IUniswapV3Adapter.UniswapV3AdapterTwapWindowZero();
        if (slippageBps_ > UNISWAP_V3_BPS_DENOMINATOR) {
            revert IUniswapV3Adapter.UniswapV3AdapterSlippageTooHigh(slippageBps_, UNISWAP_V3_BPS_DENOMINATOR);
        }

        UniswapV3AdapterStorage storage $ = uniswapV3AdapterStorage();
        $._positionManager = positionManager_;
        $._pool = pool_;
        $._vault = vault_;
        $._rewardRecipient = recipient_;
        $._twapWindow = twapWindow_;
        $._slippageBps = slippageBps_;
        // Pool-derived config (tokens/fee/full-range ticks) is written in a helper so the pool reads
        // don't pile onto this frame (the via-ir-disabled CI profile is stack-tight when the consumer
        // inlines this initializer alongside the other module inits).
        _initPoolConfig($, pool_);

        registerInterface();
        emit IUniswapV3Adapter.UniswapV3AdapterConfigured(positionManager_, pool_, $._token0, $._token1, $._fee);
        emit IUniswapV3Adapter.UniswapV3TwapWindowSet(twapWindow_);
        emit IUniswapV3Adapter.UniswapV3SlippageSet(slippageBps_);
        emit IProtocolAdapter.RewardRecipientSet(recipient_);
    }

    /// @dev Reads the pool's token0/token1/fee/tickSpacing, validates the spacing, computes the
    ///      full-range ticks, and writes them to storage. Split out of the initializer for stack room.
    function _initPoolConfig(UniswapV3AdapterStorage storage $, address pool_) private {
        IUniswapV3Pool p = IUniswapV3Pool(pool_);
        int24 spacing = p.tickSpacing();
        if (spacing <= 0) revert IUniswapV3Adapter.UniswapV3AdapterBadTickSpacing(spacing);
        (int24 tickLower, int24 tickUpper) = UniswapV3FullRangeMath.fullRangeTicks(spacing);
        $._token0 = p.token0();
        $._token1 = p.token1();
        $._fee = p.fee();
        $._tickLower = tickLower;
        $._tickUpper = tickUpper;
    }

    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IPROTOCOLADAPTER_SLOT, true)
            sstore(ERC165_MAP_IUNISWAPV3ADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  VIEWS
    //////////////////////////////////////////////////////////////////////////*//

    function asset() internal view returns (address) {
        return uniswapV3AdapterStorage()._token0;
    }

    function positionManager() internal view returns (address) {
        return uniswapV3AdapterStorage()._positionManager;
    }

    function pool() internal view returns (address) {
        return uniswapV3AdapterStorage()._pool;
    }

    function token0() internal view returns (address) {
        return uniswapV3AdapterStorage()._token0;
    }

    function token1() internal view returns (address) {
        return uniswapV3AdapterStorage()._token1;
    }

    function fee() internal view returns (uint24) {
        return uniswapV3AdapterStorage()._fee;
    }

    function tokenId() internal view returns (uint256) {
        return uniswapV3AdapterStorage()._tokenId;
    }

    function vault() internal view returns (address) {
        return uniswapV3AdapterStorage()._vault;
    }

    function twapWindow() internal view returns (uint32) {
        return uniswapV3AdapterStorage()._twapWindow;
    }

    function slippageBps() internal view returns (uint256) {
        return uniswapV3AdapterStorage()._slippageBps;
    }

    function rewardRecipient() internal view returns (address) {
        return uniswapV3AdapterStorage()._rewardRecipient;
    }

    function operator() internal view returns (address) {
        return uniswapV3AdapterStorage()._operator;
    }

    /// @dev Reverts `ProtocolAdapterUnauthorized` unless the caller is the wired operator. Placed at
    ///      the very top of `deploy`/`withdraw`/`harvest` — BEFORE the reentrancy guard — so an
    ///      unauthorized call never leaves the guard latched. Zero operator ⇒ always reverts.
    function _checkOperator() private view {
        if (msg.sender != uniswapV3AdapterStorage()._operator) {
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

    /// @notice The pool's time-weighted-average sqrt price (Q64.96) over `twapWindow`.
    /// @dev Reads `pool.observe([twapWindow, 0])` and converts the arithmetic-mean tick to a sqrt
    ///      price. **This is the only price source for NAV.** `observe` is a `view` and is resistant
    ///      to single-block manipulation (it averages the tick across the window), unlike `slot0`,
    ///      which is never read here. Rounds the mean tick toward negative infinity to match Uniswap's
    ///      `OracleLibrary.consult` (matters only for negative remainders).
    function _twapSqrtPriceX96(UniswapV3AdapterStorage storage $) private view returns (uint160) {
        uint32 window = $._twapWindow;
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = window;
        secondsAgos[1] = 0;
        (int56[] memory tickCumulatives,) = IUniswapV3Pool($._pool).observe(secondsAgos);
        int56 delta = tickCumulatives[1] - tickCumulatives[0];
        int24 meanTick = int24(delta / int56(uint56(window)));
        // Round toward negative infinity (Uniswap OracleLibrary convention).
        if (delta < 0 && (delta % int56(uint56(window)) != 0)) meanTick--;
        return UniswapV3FullRangeMath.getSqrtRatioAtTick(meanTick);
    }

    /// @notice The live liquidity of the adapter's position (0 if none minted).
    /// @dev `positions()` returns a flat 12-word tuple; decoding all 12 just to keep one blows the
    ///      stack under the via-ir-disabled CI profile, so we staticcall and read only the `liquidity`
    ///      word (index 7 → returndata offset 224). Reverts if the call fails or returns short data.
    function _positionLiquidity(UniswapV3AdapterStorage storage $) private view returns (uint128 liquidity) {
        uint256 id = $._tokenId;
        if (id == 0) return 0;
        address npm = $._positionManager;
        (bool ok, bytes memory ret) =
            npm.staticcall(abi.encodeWithSelector(INonfungiblePositionManager.positions.selector, id));
        if (!ok || ret.length < 256) revert IUniswapV3Adapter.UniswapV3AdapterPositionsCallFailed(id);
        assembly ("memory-safe") {
            // ret layout: [0]=length, then 12 abi words; liquidity is word index 7 (offset 0xe0 + 0x20).
            liquidity := mload(add(ret, 0x100))
        }
    }

    /// @notice Total assets managed, in token0 = idle token0 + the position's token0 leg at the TWAP price.
    ///         token1 is excluded, idle or in the position: the swap-free adapter can never hand it to the
    ///         vault as token0 (see the library's "NAV is token0 only"). Uncollected fees are intentionally
    ///         excluded too (forwarded raw on harvest, not part of principal NAV).
    /// @dev **Manipulation-resistance:** the position's token0 leg is derived from the TWAP sqrt price (see
    ///      `_twapSqrtPriceX96`), NEVER `slot0`. The TWAP averages the tick over `twapWindow`, so a
    ///      flash-loan spike of the spot price within one block barely moves the reported NAV — an
    ///      attacker cannot mint/redeem vault shares against a skewed price. `view` (observe is a
    ///      view). The adapter's state-changing ops are all `nonReentrant`, and VaultCore blocks
    ///      share-price-sensitive vault entries while a rebalance is in flight.
    /// @dev **token1 (#271):** keeper-funded token1 does not move NAV when it lands. A `deploy` turns idle token0
    ///      into the token0 leg, consumed at spot and counted at the TWAP, so it leaves NAV flat at spot == TWAP
    ///      and otherwise steps it by the gap, which `deploy` caps at `slippageBps` of the token0 consumed (see
    ///      the library's "Deploys happen at spot"). An adapter holding only token1 reports zero, so
    ///      `addStrategy` accepts it. The token1 is recovered only by the admin's `emergencyWithdraw`, which sends
    ///      it to the vault, outside NAV.
    function totalAssetsManaged() internal view returns (uint256) {
        UniswapV3AdapterStorage storage $ = uniswapV3AdapterStorage();
        uint256 idle0 = AdapterBaseLib.balanceOfSelf($._token0);
        uint128 liquidity = _positionLiquidity($);
        if (liquidity == 0) return idle0;
        return idle0 + _positionAmount0($, liquidity);
    }

    /// @notice The token0 that `liquidity` of the full-range position holds at the TWAP price.
    /// @dev The price source is the TWAP sqrt price (`_twapSqrtPriceX96`) — never `slot0`. Excludes
    ///      uncollected fees.
    function _positionAmount0(UniswapV3AdapterStorage storage $, uint128 liquidity)
        private
        view
        returns (uint256 amount0)
    {
        uint160 sqrtLower = UniswapV3FullRangeMath.getSqrtRatioAtTick($._tickLower);
        uint160 sqrtUpper = UniswapV3FullRangeMath.getSqrtRatioAtTick($._tickUpper);
        (amount0,) =
            UniswapV3FullRangeMath.getAmountsForLiquidity(_twapSqrtPriceX96($), sqrtLower, sqrtUpper, liquidity);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function setTwapWindow(uint32 twapWindow_) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (twapWindow_ == 0) revert IUniswapV3Adapter.UniswapV3AdapterTwapWindowZero();
        uniswapV3AdapterStorage()._twapWindow = twapWindow_;
        emit IUniswapV3Adapter.UniswapV3TwapWindowSet(twapWindow_);
    }

    function setSlippageBps(uint256 slippageBps_) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (slippageBps_ > UNISWAP_V3_BPS_DENOMINATOR) {
            revert IUniswapV3Adapter.UniswapV3AdapterSlippageTooHigh(slippageBps_, UNISWAP_V3_BPS_DENOMINATOR);
        }
        uniswapV3AdapterStorage()._slippageBps = slippageBps_;
        emit IUniswapV3Adapter.UniswapV3SlippageSet(slippageBps_);
    }

    function setRewardRecipient(address recipient) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (recipient == address(0)) revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        uniswapV3AdapterStorage()._rewardRecipient = recipient;
        emit IProtocolAdapter.RewardRecipientSet(recipient);
    }

    /// @notice Sets the authorized operator for `deploy`/`withdraw`/`harvest` (admin-only). Rejects
    ///         `address(0)` so the trio cannot be opened to an unauthenticated default.
    function setOperator(address operator_) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (operator_ == address(0)) revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        uniswapV3AdapterStorage()._operator = operator_;
        emit IProtocolAdapter.OperatorSet(operator_);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  LP LEG
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Adds the adapter's held token0 + token1 to a full-range position: `mint` the first
    ///         time, `increaseLiquidity` thereafter. Swap-free — consumes whatever the keeper funded.
    /// @dev Slippage floors `amount0Min`/`amount1Min` are the desired amounts haircut by `slippageBps`
    ///      (Uniswap enforces them; a thin/imbalanced pool that would consume too little reverts). The floors
    ///      check the keeper's funding ratio, not the price, so `_checkDeployAtTwap` also refuses a deploy whose
    ///      new token0 leg, counted at the TWAP, differs from the token0 it consumed at spot by more than
    ///      `slippageBps` (#271).
    ///      "deployed" is reported in token0 units (the amount0 actually consumed) for parity with the
    ///      single-asset adapters; token1 consumption is incidental to building the position.
    function deploy() internal returns (uint256 deployed) {
        _checkOperator();
        ReentrancyGuardLib.nonReentrantBefore();
        if (isPaused()) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IProtocolAdapter.ProtocolAdapterPaused();
        }
        UniswapV3AdapterStorage storage $ = uniswapV3AdapterStorage();
        address t0 = $._token0;
        address t1 = $._token1;
        uint256 bal0 = AdapterBaseLib.balanceOfSelf(t0);
        uint256 bal1 = AdapterBaseLib.balanceOfSelf(t1);
        if (bal0 == 0 && bal1 == 0) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IProtocolAdapter.ProtocolAdapterNothingToDeploy();
        }

        address npm = $._positionManager;
        AdapterBaseLib.forceApprove(t0, npm, bal0);
        AdapterBaseLib.forceApprove(t1, npm, bal1);

        // Mint the first time, increase thereafter. Kept in helpers so each MintParams/IncreaseParams
        // struct gets a fresh stack frame (the via-ir-disabled CI profile is stack-tight otherwise).
        (uint128 added, uint256 amount0) =
            $._tokenId == 0 ? _mintPosition($, bal0, bal1) : _increasePosition($, bal0, bal1);
        _checkDeployAtTwap($, added, amount0);

        // Clear residual approvals (defensive; mint/increase usually consume the exact desired).
        AdapterBaseLib.forceApprove(t0, npm, 0);
        AdapterBaseLib.forceApprove(t1, npm, 0);

        deployed = amount0;
        emit IProtocolAdapter.Deployed(t0, amount0);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @dev Mints the initial full-range position from `(bal0, bal1)`; stores the new id and returns
    ///      the token0 actually consumed. Slippage floors are the balances haircut by `slippageBps`.
    function _mintPosition(UniswapV3AdapterStorage storage $, uint256 bal0, uint256 bal1)
        private
        returns (uint128, uint256)
    {
        uint256 bps = $._slippageBps;
        (uint256 newId, uint128 liquidity, uint256 a0,) = INonfungiblePositionManager($._positionManager)
            .mint(
                INonfungiblePositionManager.MintParams({
                    token0: $._token0,
                    token1: $._token1,
                    fee: $._fee,
                    tickLower: $._tickLower,
                    tickUpper: $._tickUpper,
                    amount0Desired: bal0,
                    amount1Desired: bal1,
                    amount0Min: (bal0 * (UNISWAP_V3_BPS_DENOMINATOR - bps)) / UNISWAP_V3_BPS_DENOMINATOR,
                    amount1Min: (bal1 * (UNISWAP_V3_BPS_DENOMINATOR - bps)) / UNISWAP_V3_BPS_DENOMINATOR,
                    recipient: address(this),
                    deadline: block.timestamp
                })
            );
        $._tokenId = newId;
        emit IUniswapV3Adapter.UniswapV3PositionMinted(newId, liquidity);
        return (liquidity, a0);
    }

    /// @dev Adds `(bal0, bal1)` to the existing position; returns the liquidity added and the token0 actually
    ///      consumed.
    function _increasePosition(UniswapV3AdapterStorage storage $, uint256 bal0, uint256 bal1)
        private
        returns (uint128, uint256)
    {
        uint256 bps = $._slippageBps;
        (uint128 liquidity, uint256 a0,) = INonfungiblePositionManager($._positionManager)
            .increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams({
                    tokenId: $._tokenId,
                    amount0Desired: bal0,
                    amount1Desired: bal1,
                    amount0Min: (bal0 * (UNISWAP_V3_BPS_DENOMINATOR - bps)) / UNISWAP_V3_BPS_DENOMINATOR,
                    amount1Min: (bal1 * (UNISWAP_V3_BPS_DENOMINATOR - bps)) / UNISWAP_V3_BPS_DENOMINATOR,
                    deadline: block.timestamp
                })
            );
        return (liquidity, a0);
    }

    /// @dev Refuses a deploy that would step NAV by more than `slippageBps` of the token0 it consumed (#271).
    ///      The pool prices a mint or increase at spot, so it takes `consumed0` token0, while NAV counts the
    ///      `added` liquidity's token0 leg at the TWAP. NAV therefore moves by the difference, about
    ///      `consumed0 × (√(P_spot / P_twap) − 1)`, and anyone who can move spot inside the permissionless
    ///      `rebalance()` could choose it. Reverting rolls the deploy back, and the StrategyManager reports the
    ///      failure and leaves the token0 idle (and counted), so the worst case is a skipped deploy. Compares
    ///      the two amounts the deploy produced and never reads `slot0`. The 2 wei allowance absorbs the
    ///      pool rounding the consumed amount up and the TWAP leg rounding down, so `slippageBps == 0` still
    ///      deploys at spot == TWAP.
    function _checkDeployAtTwap(UniswapV3AdapterStorage storage $, uint128 added, uint256 consumed0) private view {
        uint256 counted0 = _positionAmount0($, added);
        uint256 gap = counted0 > consumed0 ? counted0 - consumed0 : consumed0 - counted0;
        if (gap > (consumed0 * $._slippageBps) / UNISWAP_V3_BPS_DENOMINATOR + 2) {
            revert IUniswapV3Adapter.UniswapV3AdapterDeployOffTwap(consumed0, counted0);
        }
    }

    /// @notice Recalls up to `amount` of token0 to `to` from the adapter's idle token0. Shortfall-honest: the
    ///         returned value is the REAL token0 sent to `to`, never over-reported.
    /// @dev Never removes liquidity (#271): a decrease pays out at spot against a TWAP-counted token0 leg, so
    ///      with spot above the TWAP the StrategyManager would see a value loss and revert the whole
    ///      `rebalance()` (see the library's "Withdraw pays idle token0 only"). Asking for more than the idle
    ///      token0 is therefore an honest partial recall: the unpaid part stays in the counted token0 leg. The
    ///      position is unwound only by the admin's `emergencyWithdraw` (see the library's "Exit needs the
    ///      admin").
    function withdraw(uint256 amount, address to) internal returns (uint256 withdrawn) {
        _checkOperator();
        ReentrancyGuardLib.nonReentrantBefore();
        UniswapV3AdapterStorage storage $ = uniswapV3AdapterStorage();
        // Recipient pin: a recall may ONLY land in the adapter's own vault. The legit caller (the
        // StrategyManager) already passes the vault; this makes redirecting the position impossible.
        if (to != $._vault) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IProtocolAdapter.ProtocolAdapterInvalidRecipient(to);
        }
        withdrawn = AdapterBaseLib.transferHonest($._token0, to, amount);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Collects accrued swap fees (token0 + token1) and forwards them RAW to the reward
    ///         recipient. Fees are the yield distribution; they are NOT counted in NAV.
    /// @dev Collects with `tokensOwed*` maxima straight to the recipient. Graceful on a zero-fee position
    ///      (collect returns 0). Because principal (live liquidity) is never decreased here, a non-zero
    ///      collect can only be accrued fees — never principal — so it cannot drain the LP position. Idle
    ///      balances are never forwarded: idle token0 is NAV, and idle token1 waits for the next `deploy`.
    function harvest() internal {
        _checkOperator();
        ReentrancyGuardLib.nonReentrantBefore();
        UniswapV3AdapterStorage storage $ = uniswapV3AdapterStorage();
        uint256 id = $._tokenId;
        if (id == 0) {
            ReentrancyGuardLib.nonReentrantAfter();
            return; // no position: nothing to collect
        }
        address recipient = $._rewardRecipient;
        // Collect everything owed (fees only — we did not decrease liquidity) to the recipient.
        (uint256 f0, uint256 f1) = INonfungiblePositionManager($._positionManager)
            .collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: id, recipient: recipient, amount0Max: type(uint128).max, amount1Max: type(uint128).max
                })
            );
        if (f0 > 0) emit IProtocolAdapter.RewardsForwarded($._token0, recipient, f0);
        if (f1 > 0) emit IProtocolAdapter.RewardsForwarded($._token1, recipient, f1);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Fully exits: removes ALL liquidity, collects everything, and sends both tokens to the
    ///         vault. Admin-gated; runs even when paused/stopped (the emergency path).
    /// @dev No slippage floor (min == 0): an emergency prioritizes getting funds out. Both token0 and
    ///      token1 (principal + any accrued fees, indistinguishable once collected) go to the vault.
    ///      This is the only way the position is unwound and the only way token1 leaves the adapter (see
    ///      "Exit needs the admin"). The token0 replaces the token0 leg and idle token0 NAV already counted,
    ///      but the decrease pays at spot, so the vault's NAV steps by about `leg0 × (√(P_twap / P_spot) − 1)`
    ///      (plus any collected token0 fees), with no floor: call it while spot sits near the TWAP. The token1
    ///      was never NAV and lands in the vault outside it.
    function emergencyWithdraw() internal returns (uint256 recovered) {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ReentrancyGuardLib.nonReentrantBefore();
        UniswapV3AdapterStorage storage $ = uniswapV3AdapterStorage();
        address t0 = $._token0;
        address t1 = $._token1;
        address to = $._vault;

        uint128 liquidity = _positionLiquidity($);
        // Remove ALL liquidity and collect to the adapter (helper reused; keeps the structs off this
        // frame for the stack-tight CI profile). min == 0: emergency prioritizes exit over slippage.
        if (liquidity > 0) _decreaseAndCollect($, liquidity);

        // Sweep the adapter's whole balance of both tokens to the vault.
        recovered = AdapterBaseLib.transferHonest(t0, to, AdapterBaseLib.balanceOfSelf(t0));
        uint256 bal1 = AdapterBaseLib.balanceOfSelf(t1);
        if (bal1 > 0) AdapterBaseLib.transferHonest(t1, to, bal1);

        emit IProtocolAdapter.EmergencyWithdrawn(t0, to, recovered);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Decreases `liquidityToRemove` from the position and collects the freed token0 + token1 (plus
    ///      any accrued fees) to the adapter. Used only by `emergencyWithdraw`.
    function _decreaseAndCollect(UniswapV3AdapterStorage storage $, uint128 liquidityToRemove) private {
        address npm = $._positionManager;
        uint256 id = $._tokenId;
        // Free the liquidity (amounts become owed-tokens; not transferred yet).
        INonfungiblePositionManager(npm)
            .decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: id, liquidity: liquidityToRemove, amount0Min: 0, amount1Min: 0, deadline: block.timestamp
                })
            );
        // Collect the freed amounts to the adapter. This also collects any accrued fees, since they are
        // owed-tokens too; the emergency exit sweeps them to the vault with the principal.
        INonfungiblePositionManager(npm)
            .collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: id, recipient: address(this), amount0Max: type(uint128).max, amount1Max: type(uint128).max
                })
            );
    }
}
