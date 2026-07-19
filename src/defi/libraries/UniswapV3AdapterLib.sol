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
///         **Valuation — TWAP, never spot (the central risk).** NAV reads the pool's TWAP via
///         `pool.observe(twapWindow)`, converts the arithmetic-mean tick to a sqrt price, and derives
///         the position's `(amount0, amount1)` at that price (token1 valued back into token0). It
///         **never** reads `slot0`: the spot tick is single-block manipulable (a flash swap can push
///         it arbitrarily), and pricing vault shares off spot would let an attacker mint/redeem at a
///         skewed NAV. The TWAP averages the tick over the whole window, so a one-block spike barely
///         moves it. Uncollected fees are NOT counted in NAV (they are the yield distribution,
///         forwarded raw on `harvest`).
///
///         **Shortfall-honest withdraw.** `withdraw(amount, to)` is token0-denominated: the adapter
///         removes enough liquidity to free ~`amount` of token0-equivalent (sized via the TWAP
///         price), collects, sends the freed token0 to `to`, and routes the freed token1 to `to`
///         too. It returns the REAL token0 delta and never over-reports; the StrategyManager's
///         upstream shortfall check absorbs any remainder (a single decreaseLiquidity frees token0
///         and token1 in the pool's ratio, so the token0 freed can be < `amount`).
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
        require(ok && ret.length >= 256, "positions");
        assembly ("memory-safe") {
            // ret layout: [0]=length, then 12 abi words; liquidity is word index 7 (offset 0xe0 + 0x20).
            liquidity := mload(add(ret, 0x100))
        }
    }

    /// @notice Total assets managed, denominated in token0 = idle token0 held + the LP position valued
    ///         at the TWAP price. Uncollected fees are intentionally excluded (forwarded raw on
    ///         harvest, not part of principal NAV).
    /// @dev **Manipulation-resistance:** the position is valued from the TWAP sqrt price (see
    ///      `_twapSqrtPriceX96`), NEVER `slot0`. The TWAP averages the tick over `twapWindow`, so a
    ///      flash-loan spike of the spot price within one block barely moves the reported NAV — an
    ///      attacker cannot mint/redeem vault shares against a skewed price. `view` (observe is a
    ///      view). The adapter's state-changing ops are all `nonReentrant`, and VaultCore blocks
    ///      share-price-sensitive vault entries while a rebalance is in flight.
    function totalAssetsManaged() internal view returns (uint256) {
        UniswapV3AdapterStorage storage $ = uniswapV3AdapterStorage();
        uint256 idle0 = AdapterBaseLib.balanceOfSelf($._token0);
        uint128 liquidity = _positionLiquidity($);
        if (liquidity == 0) return idle0;
        return idle0 + _positionValueInToken0($, liquidity);
    }

    /// @notice Values `liquidity` of the full-range position in token0 units at the TWAP price.
    /// @dev Shared by `totalAssetsManaged` and `withdraw`'s sizing. The price source is the TWAP sqrt
    ///      price (`_twapSqrtPriceX96`) — never `slot0`. Excludes uncollected fees.
    function _positionValueInToken0(UniswapV3AdapterStorage storage $, uint128 liquidity)
        private
        view
        returns (uint256)
    {
        uint160 sqrtTwap = _twapSqrtPriceX96($);
        uint160 sqrtLower = UniswapV3FullRangeMath.getSqrtRatioAtTick($._tickLower);
        uint160 sqrtUpper = UniswapV3FullRangeMath.getSqrtRatioAtTick($._tickUpper);
        (uint256 amount0, uint256 amount1) =
            UniswapV3FullRangeMath.getAmountsForLiquidity(sqrtTwap, sqrtLower, sqrtUpper, liquidity);
        return UniswapV3FullRangeMath.valueInToken0(amount0, amount1, sqrtTwap);
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
    ///      (Uniswap enforces them; a thin/imbalanced pool that would consume too little reverts).
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
        uint256 amount0 = $._tokenId == 0 ? _mintPosition($, bal0, bal1) : _increasePosition($, bal0, bal1);

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
        returns (uint256 amount0)
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
        return a0;
    }

    /// @dev Adds `(bal0, bal1)` to the existing position; returns the token0 actually consumed.
    function _increasePosition(UniswapV3AdapterStorage storage $, uint256 bal0, uint256 bal1)
        private
        returns (uint256 amount0)
    {
        uint256 bps = $._slippageBps;
        (, uint256 a0,) = INonfungiblePositionManager($._positionManager)
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
        return a0;
    }

    /// @notice Withdraws ~`amount` of token0-equivalent to `to` by removing liquidity, then collecting
    ///         and forwarding the freed token0 (and any freed token1) to `to`. Shortfall-honest: the
    ///         returned value is the REAL token0 delta sent to `to`, never over-reported.
    /// @dev Sizing: at the TWAP price the position holds `amount0 + amount1·price` of token0-value per
    ///      its full liquidity; we remove a pro-rata fraction `amount / positionValue0` of liquidity.
    ///      A single decreaseLiquidity frees token0 AND token1 in the current pool ratio, so the
    ///      token0 freed for a given `amount` can be less than `amount` (the rest comes out as
    ///      token1). That is the documented two-token caveat — we report the honest token0 delta and
    ///      forward the token1 to `to` as well so no value is stranded in the adapter.
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
        uint128 liquidity = _positionLiquidity($);
        if (liquidity == 0 || amount == 0) {
            ReentrancyGuardLib.nonReentrantAfter();
            return 0;
        }

        // Size the liquidity to remove pro-rata to `amount` over the TWAP-valued position (helper keeps
        // the heavy locals off this frame for the stack-tight CI profile).
        uint128 liquidityToRemove = _liquidityToFree($, liquidity, amount);

        // Honest token0 delta is exactly what the position manager sends to `to` (collect goes to `to`).
        (withdrawn,) = _decreaseAndCollect($, liquidityToRemove, to);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Collects accrued swap fees (token0 + token1) and forwards them RAW to the reward
    ///         recipient. Fees are the yield distribution; they are NOT counted in NAV.
    /// @dev Collects with `tokensOwed*` maxima to the adapter, then forwards each token's full balance.
    ///      Graceful on a zero-fee position (collect returns 0, forward is a no-op). Because principal
    ///      (live liquidity) is never decreased here, a non-zero collect after a deploy can only be
    ///      accrued fees — never principal — so forwarding it raw cannot drain the LP position.
    ///      **Caveat:** `forwardRewardRaw` sweeps the adapter's ENTIRE token0/token1 balance, so any
    ///      idle token0/token1 not yet deployed (incl. ~1 wei mint dust) is forwarded too — reducing
    ///      the idle component of NAV by that amount. The keeper should `deploy()` idle funds before
    ///      `harvest()` so only genuine fees are distributed; the LP principal is never at risk.
    function harvest() internal {
        _checkOperator();
        ReentrancyGuardLib.nonReentrantBefore();
        UniswapV3AdapterStorage storage $ = uniswapV3AdapterStorage();
        uint256 id = $._tokenId;
        if (id == 0) {
            ReentrancyGuardLib.nonReentrantAfter();
            return; // no position: nothing to collect
        }
        // Collect everything owed (fees only — we did not decrease liquidity) to the adapter.
        INonfungiblePositionManager($._positionManager)
            .collect(
                INonfungiblePositionManager.CollectParams({
                tokenId: id, recipient: address(this), amount0Max: type(uint128).max, amount1Max: type(uint128).max
            })
            );

        address recipient = $._rewardRecipient;
        uint256 f0 = AdapterBaseLib.forwardRewardRaw($._token0, recipient);
        if (f0 > 0) emit IProtocolAdapter.RewardsForwarded($._token0, recipient, f0);
        uint256 f1 = AdapterBaseLib.forwardRewardRaw($._token1, recipient);
        if (f1 > 0) emit IProtocolAdapter.RewardsForwarded($._token1, recipient, f1);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Fully exits: removes ALL liquidity, collects everything, and sends both tokens to the
    ///         vault. Admin-gated; runs even when paused/stopped (the emergency path).
    /// @dev No slippage floor (min == 0): an emergency prioritizes getting funds out. Both token0 and
    ///      token1 (principal + any accrued fees, indistinguishable once collected) go to the vault.
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
        if (liquidity > 0) _decreaseAndCollect($, liquidity, address(this));

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

    /// @dev Sizes how much liquidity to remove to free ~`amount` of token0-equivalent, pro-rata over
    ///      the TWAP-valued position. Caps at the whole `liquidity` when `amount` >= the position
    ///      value; rounds a tiny non-zero ask up to 1 so dust still frees something. Isolated in a
    ///      helper to keep the heavy valuation locals off `withdraw`'s frame (stack-tight CI profile).
    function _liquidityToFree(UniswapV3AdapterStorage storage $, uint128 liquidity, uint256 amount)
        private
        view
        returns (uint128 liquidityToRemove)
    {
        uint256 positionValue0 = _positionValueInToken0($, liquidity);
        if (positionValue0 == 0 || amount >= positionValue0) return liquidity;
        liquidityToRemove = uint128(UniswapV3FullRangeMath.mulDiv(liquidity, amount, positionValue0));
        if (liquidityToRemove == 0) liquidityToRemove = 1;
    }

    /// @dev Decreases `liquidityToRemove` from the position and collects the freed token0 + token1
    ///      directly to `to`. Returns the real `(token0, token1)` amounts the position manager sent —
    ///      the token0 figure is the shortfall-honest value `withdraw` reports.
    function _decreaseAndCollect(UniswapV3AdapterStorage storage $, uint128 liquidityToRemove, address to)
        private
        returns (uint256 collected0, uint256 collected1)
    {
        address npm = $._positionManager;
        uint256 id = $._tokenId;
        // Free the liquidity (amounts become owed-tokens; not transferred yet).
        INonfungiblePositionManager(npm)
            .decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: id, liquidity: liquidityToRemove, amount0Min: 0, amount1Min: 0, deadline: block.timestamp
            })
            );
        // Collect the freed amounts directly to `to` (this withdraw intentionally also sweeps any
        // accrued fees to `to`, since they are owed-tokens too — acceptable: it returns value to the
        // vault, never strands it in the adapter).
        (collected0, collected1) = INonfungiblePositionManager(npm)
            .collect(
                INonfungiblePositionManager.CollectParams({
                tokenId: id, recipient: to, amount0Max: type(uint128).max, amount1Max: type(uint128).max
            })
            );
    }
}
