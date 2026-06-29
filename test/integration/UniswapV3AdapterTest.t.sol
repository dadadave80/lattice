// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {UniswapV3Adapter} from "@lattice/defi/UniswapV3Adapter.sol";
import {UniswapV3AdapterLib} from "@lattice/defi/libraries/UniswapV3AdapterLib.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {IUniswapV3Adapter} from "@lattice/interfaces/defi/IUniswapV3Adapter.sol";
import {INonfungiblePositionManager} from "@lattice/interfaces/external/INonfungiblePositionManager.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {UniswapV3FullRangeMath} from "@lattice/utils/libraries/UniswapV3FullRangeMath.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                               MOCK ERC20
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal 18-decimal ERC20 for both pool tokens.
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory n, string memory s) {
        name = n;
        symbol = s;
    }

    function mint(address to, uint256 a) external {
        balanceOf[to] += a;
    }

    function transfer(address to, uint256 a) external returns (bool) {
        require(balanceOf[msg.sender] >= a, "bal");
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
        return true;
    }

    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        require(balanceOf[f] >= a, "bal");
        require(allowance[f][msg.sender] >= a, "allow");
        allowance[f][msg.sender] -= a;
        balanceOf[f] -= a;
        balanceOf[t] += a;
        return true;
    }

    function approve(address s, uint256 a) external returns (bool) {
        allowance[msg.sender][s] = a;
        return true;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                              MOCK UNI V3 POOL
//////////////////////////////////////////////////////////////////////////*//

/// @notice Mock Uniswap V3 pool. Exposes a **settable TWAP tick** (drives `observe`) and a SEPARATE
///         **settable spot tick** (drives `slot0`). The two are independent so a test can spike spot
///         without moving the TWAP — proving the adapter values from `observe`, never `slot0`.
/// @dev `observe([w,0])` returns a tick-cumulative series whose mean over `w` equals `twapTick`
///      exactly: tickCumulatives = [0, twapTick * w] so `(c[1]-c[0])/w == twapTick`.
contract MockUniV3Pool {
    address public token0;
    address public token1;
    uint24 public fee;
    int24 public tickSpacing;

    int24 public twapTick; // drives observe() — the manipulation-resistant price
    int24 public spotTick; // drives slot0() — single-block manipulable spot

    constructor(address t0, address t1, uint24 fee_, int24 spacing_, int24 initialTick) {
        token0 = t0;
        token1 = t1;
        fee = fee_;
        tickSpacing = spacing_;
        twapTick = initialTick;
        spotTick = initialTick;
    }

    function setTwapTick(int24 t) external {
        twapTick = t;
    }

    function setSpotTick(int24 t) external {
        spotTick = t;
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        // secondsAgos == [w, 0]; produce cumulatives whose difference / w == twapTick.
        uint32 w = secondsAgos[0];
        tickCumulatives = new int56[](2);
        secondsPerLiquidityCumulativeX128s = new uint160[](2);
        tickCumulatives[0] = 0;
        tickCumulatives[1] = int56(twapTick) * int56(uint56(w));
    }

    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16, uint16, uint16, uint8, bool) {
        sqrtPriceX96 = UniswapV3FullRangeMath.getSqrtRatioAtTick(spotTick);
        tick = spotTick;
        return (sqrtPriceX96, tick, 0, 0, 0, 0, true);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                         MOCK POSITION MANAGER (NFPM)
//////////////////////////////////////////////////////////////////////////*//

/// @notice Mock NonfungiblePositionManager with internal liquidity↔amounts bookkeeping consistent
///         with the mock pool's TWAP price (uses the SAME `UniswapV3FullRangeMath` the adapter uses,
///         so a mint→value→withdraw round-trips exactly). Pulls tokens on mint/increase, holds them,
///         pays them back on decrease+collect. Supports a settable fee accrual that `collect` pays.
contract MockPositionManager {
    MockUniV3Pool public pool;
    MockERC20 public token0;
    MockERC20 public token1;

    uint256 public nextId = 1;

    struct Position {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint128 owed0; // freed-but-uncollected token0 (from decrease) + accrued fee0
        uint128 owed1;
    }

    mapping(uint256 => Position) public pos;

    constructor(MockUniV3Pool p, MockERC20 t0, MockERC20 t1) {
        pool = p;
        token0 = t0;
        token1 = t1;
    }

    /// @dev Liquidity mintable from `(a0, a1)` and the amounts it actually consumes, at the TWAP price
    ///      over [tickLower, tickUpper]. Uses the SAME math the adapter values with, so round-trips.
    function _quote(int24 tickLower, int24 tickUpper, uint256 a0, uint256 a1)
        internal
        view
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        uint160 sc = UniswapV3FullRangeMath.getSqrtRatioAtTick(pool.twapTick());
        uint160 sl = UniswapV3FullRangeMath.getSqrtRatioAtTick(tickLower);
        uint160 su = UniswapV3FullRangeMath.getSqrtRatioAtTick(tickUpper);
        liquidity = UniswapV3FullRangeMath.getLiquidityForAmounts(sc, sl, su, a0, a1);
        (amount0, amount1) = UniswapV3FullRangeMath.getAmountsForLiquidity(sc, sl, su, liquidity);
    }

    /// @dev Amounts owed when removing `liq` liquidity, at the TWAP price over [tickLower, tickUpper].
    function _amountsFor(int24 tickLower, int24 tickUpper, uint128 liq)
        internal
        view
        returns (uint256 amount0, uint256 amount1)
    {
        uint160 sc = UniswapV3FullRangeMath.getSqrtRatioAtTick(pool.twapTick());
        uint160 sl = UniswapV3FullRangeMath.getSqrtRatioAtTick(tickLower);
        uint160 su = UniswapV3FullRangeMath.getSqrtRatioAtTick(tickUpper);
        (amount0, amount1) = UniswapV3FullRangeMath.getAmountsForLiquidity(sc, sl, su, liq);
    }

    function mint(INonfungiblePositionManager.MintParams calldata p)
        external
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        (liquidity, amount0, amount1) = _quote(p.tickLower, p.tickUpper, p.amount0Desired, p.amount1Desired);
        require(amount0 >= p.amount0Min, "amount0Min");
        require(amount1 >= p.amount1Min, "amount1Min");
        require(token0.transferFrom(msg.sender, address(this), amount0), "pull0");
        require(token1.transferFrom(msg.sender, address(this), amount1), "pull1");
        tokenId = nextId++;
        Position storage pp = pos[tokenId];
        pp.owner = p.recipient;
        pp.tickLower = p.tickLower;
        pp.tickUpper = p.tickUpper;
        pp.liquidity = liquidity;
    }

    function increaseLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams calldata p)
        external
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        Position storage pp = pos[p.tokenId];
        (liquidity, amount0, amount1) = _quote(pp.tickLower, pp.tickUpper, p.amount0Desired, p.amount1Desired);
        require(amount0 >= p.amount0Min, "amount0Min");
        require(amount1 >= p.amount1Min, "amount1Min");
        require(token0.transferFrom(msg.sender, address(this), amount0), "pull0");
        require(token1.transferFrom(msg.sender, address(this), amount1), "pull1");
        pp.liquidity += liquidity;
    }

    function decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata p)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        Position storage pp = pos[p.tokenId];
        require(pp.liquidity >= p.liquidity, "liq");
        (amount0, amount1) = _amountsFor(pp.tickLower, pp.tickUpper, p.liquidity);
        require(amount0 >= p.amount0Min, "amount0Min");
        require(amount1 >= p.amount1Min, "amount1Min");
        pp.liquidity -= p.liquidity;
        pp.owed0 += uint128(amount0);
        pp.owed1 += uint128(amount1);
    }

    function collect(INonfungiblePositionManager.CollectParams calldata p)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        Position storage pp = pos[p.tokenId];
        amount0 = pp.owed0 < p.amount0Max ? pp.owed0 : p.amount0Max;
        amount1 = pp.owed1 < p.amount1Max ? pp.owed1 : p.amount1Max;
        pp.owed0 -= uint128(amount0);
        pp.owed1 -= uint128(amount1);
        if (amount0 > 0) require(token0.transfer(p.recipient, amount0), "send0");
        if (amount1 > 0) require(token1.transfer(p.recipient, amount1), "send1");
    }

    /// @notice Test helper: the position's tick range (avoids decoding the 12-field `positions` tuple
    ///         in test bodies, which overflows the stack under the via-ir-disabled profile).
    function positionTicks(uint256 tokenId) external view returns (int24 tickLower, int24 tickUpper) {
        Position storage pp = pos[tokenId];
        return (pp.tickLower, pp.tickUpper);
    }

    /// @notice Simulate accrued swap fees claimable via `collect` (does not change live liquidity).
    function accrueFees(uint256 tokenId, uint128 fee0, uint128 fee1) external {
        Position storage pp = pos[tokenId];
        pp.owed0 += fee0;
        pp.owed1 += fee1;
        // Fund the manager so collect can pay them out.
        token0.mint(address(this), fee0);
        token1.mint(address(this), fee1);
    }

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address t0,
            address t1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        // Assign named returns individually (avoids a 12-tuple expression that blows the stack under
        // the via-ir-disabled profile). nonce/operator/feeGrowth stay at their zero defaults.
        Position storage pp = pos[tokenId];
        t0 = address(token0);
        t1 = address(token1);
        fee = pool.fee();
        tickLower = pp.tickLower;
        tickUpper = pp.tickUpper;
        liquidity = pp.liquidity;
        tokensOwed0 = pp.owed0;
        tokensOwed1 = pp.owed1;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                 MOCK ADAPTER
//////////////////////////////////////////////////////////////////////////*//

/// @notice Adapter composed with Pausable + EmergencyStop facets (as a real Diamond would).
contract MockUniV3Adapter is UniswapV3Adapter, Pausable, EmergencyStop {
    function initialize(
        address admin_,
        address positionManager_,
        address pool_,
        address vault_,
        address recipient_,
        uint32 twapWindow_,
        uint256 slippageBps_
    ) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        ReentrancyGuardLib.__ReentrancyGuard_init();
        PausableLib.__Pausable_init();
        EmergencyStopLib.__EmergencyStop_init();
        UniswapV3AdapterLib.__UniswapV3Adapter_init(
            positionManager_, pool_, vault_, recipient_, twapWindow_, slippageBps_
        );
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) external view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                   TESTS
//////////////////////////////////////////////////////////////////////////*//

contract UniswapV3AdapterTest is Test {
    MockERC20 token0;
    MockERC20 token1;
    MockUniV3Pool pool;
    MockPositionManager npm;
    MockUniV3Adapter adapter;

    address admin = address(0xAD);
    address guardian = address(0x6);
    address vault = address(0x7A17);
    address treasury = address(0x7E0);

    uint24 constant FEE = 3000;
    int24 constant TICK_SPACING = 60;
    uint32 constant TWAP_WINDOW = 1800;
    uint256 constant SLIPPAGE_BPS = 100; // 1%
    // Tick 0 == price 1.0 (1 token0 == 1 token1). A clean baseline for a 1:1 pair.
    int24 constant INITIAL_TICK = 0;

    function setUp() public {
        // Deploy two tokens; ensure token0 < token1 by address (Uniswap sort) is not required for the
        // mock (it stores whatever we pass), but we keep them distinct.
        token0 = new MockERC20("Token0", "TK0");
        token1 = new MockERC20("Token1", "TK1");
        pool = new MockUniV3Pool(address(token0), address(token1), FEE, TICK_SPACING, INITIAL_TICK);
        npm = new MockPositionManager(pool, token0, token1);

        adapter = new MockUniV3Adapter();
        adapter.initialize(admin, address(npm), address(pool), vault, treasury, TWAP_WINDOW, SLIPPAGE_BPS);
        vm.startPrank(admin);
        adapter.addGuardian(guardian);
        // Authorize this test contract as the operator so the direct deploy/withdraw/harvest calls
        // (which the StrategyManager would make in production) pass the operator gate.
        adapter.setOperator(address(this));
        vm.stopPrank();
    }

    /// @dev Fund the adapter with balanced token0/token1 (the keeper's job — swap-free adapter).
    function _fund(uint256 amount0, uint256 amount1) internal {
        token0.mint(address(adapter), amount0);
        token1.mint(address(adapter), amount1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  DEPLOY
    //////////////////////////////////////////////////////////////////////////*//

    function test_Deploy_MintsFullRangePosition_ConsumesBothTokens() public {
        _fund(1_000e18, 1_000e18);
        uint256 deployed = adapter.deploy();
        assertGt(deployed, 0, "reports token0 deployed");
        assertGt(adapter.tokenId(), 0, "position minted");
        // Both tokens consumed into the position (at price 1.0 a balanced add consumes ~all of both).
        // Up to 1 wei of each may remain as rounding dust from the liquidity<->amount conversion — it
        // is NOT lost (idle token0 is counted in NAV; token1 dust is swept by the next harvest).
        assertLe(token0.balanceOf(address(adapter)), 1, "token0 consumed (<=1 wei dust)");
        assertLe(token1.balanceOf(address(adapter)), 1, "token1 consumed (<=1 wei dust)");
        // Position is full-range: ticks are the min/max usable aligned to spacing.
        (int24 lo, int24 hi) = UniswapV3FullRangeMath.fullRangeTicks(TICK_SPACING);
        (int24 tickLower, int24 tickUpper) = npm.positionTicks(adapter.tokenId());
        assertEq(tickLower, lo, "full-range lower");
        assertEq(tickUpper, hi, "full-range upper");
    }

    function test_Deploy_IncreasesExistingPosition() public {
        _fund(1_000e18, 1_000e18);
        adapter.deploy();
        uint256 id = adapter.tokenId();
        uint256 navAfterFirst = adapter.totalAssetsManaged();

        _fund(500e18, 500e18);
        adapter.deploy();
        assertEq(adapter.tokenId(), id, "same position id (increase, not re-mint)");
        assertApproxEqRel(adapter.totalAssetsManaged(), navAfterFirst + 1_000e18, 1e15, "NAV grew by added value");
    }

    function test_Deploy_RevertsWhenNothingToDeploy() public {
        vm.expectRevert(IProtocolAdapter.ProtocolAdapterNothingToDeploy.selector);
        adapter.deploy();
    }

    function test_Deploy_RevertsWhenPaused() public {
        _fund(1_000e18, 1_000e18);
        vm.prank(admin);
        adapter.pause();
        vm.expectRevert(IProtocolAdapter.ProtocolAdapterPaused.selector);
        adapter.deploy();
    }

    function test_Deploy_RevertsWhenStopped() public {
        _fund(1_000e18, 1_000e18);
        vm.prank(guardian);
        adapter.emergencyStop("incident");
        vm.expectRevert(IProtocolAdapter.ProtocolAdapterPaused.selector);
        adapter.deploy();
    }

    function test_Deploy_EnforcesSlippageMinOut() public {
        // Fund token0 only: at price 1.0 the in-range mint binds on the MIN of the two single-token
        // liquidities, so amount1Desired == 0 ⇒ liquidity 0 ⇒ amount0 consumed 0 < amount0Min floor.
        token0.mint(address(adapter), 1_000e18);
        vm.expectRevert(bytes("amount0Min"));
        adapter.deploy();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                  TOTAL ASSETS — TWAP VALUATION (CENTRAL RISK)
    //////////////////////////////////////////////////////////////////////////*//

    function test_TotalAssets_ValuesPositionViaTwap() public {
        _fund(1_000e18, 1_000e18);
        adapter.deploy();
        // At price 1.0 the position holds ~1000 token0 + ~1000 token1, valued in token0 == ~2000.
        assertApproxEqRel(adapter.totalAssetsManaged(), 2_000e18, 1e15, "TWAP-valued NAV ~2000 token0");
    }

    /// @notice THE key property: a spiked `slot0` spot price does NOT move NAV — valuation reads only
    ///         the TWAP via `observe`. We move spot far away and assert NAV is unchanged.
    function test_TotalAssets_IgnoresSpotPriceSpike() public {
        _fund(1_000e18, 1_000e18);
        adapter.deploy();
        uint256 navBefore = adapter.totalAssetsManaged();

        // Attacker flash-spikes spot far up (and then far down) — TWAP tick is untouched.
        pool.setSpotTick(200_000);
        assertEq(adapter.totalAssetsManaged(), navBefore, "NAV unchanged by spot spike up");
        pool.setSpotTick(-200_000);
        assertEq(adapter.totalAssetsManaged(), navBefore, "NAV unchanged by spot spike down");
        // Sanity: spot really did change (proving spot moved and was still ignored by valuation).
        assertEq(pool.spotTick(), -200_000, "spot tick actually moved");
    }

    /// @notice A genuine TWAP move changes NAV in the correct direction: raising the TWAP tick raises
    ///         the token1/token0 price, so token1 in the position is worth fewer token0 ⇒ NAV (in
    ///         token0) decreases; lowering the tick increases it.
    function test_TotalAssets_TwapMoveChangesNav() public {
        _fund(1_000e18, 1_000e18);
        adapter.deploy();
        uint256 navAt1 = adapter.totalAssetsManaged();

        pool.setTwapTick(6932); // ~price 2.0 (token1 per token0): token1 worth less in token0 terms
        uint256 navUp = adapter.totalAssetsManaged();
        assertLt(navUp, navAt1, "higher token1/token0 price lowers token0-denominated NAV");

        pool.setTwapTick(-6932); // ~price 0.5: token1 worth more in token0 terms
        uint256 navDown = adapter.totalAssetsManaged();
        assertGt(navDown, navAt1, "lower token1/token0 price raises token0-denominated NAV");
    }

    function test_TotalAssets_IncludesIdleToken0() public {
        _fund(1_000e18, 1_000e18);
        adapter.deploy();
        uint256 nav = adapter.totalAssetsManaged();
        // Drop extra idle token0 into the adapter (not yet deployed): NAV rises by exactly that.
        token0.mint(address(adapter), 123e18);
        assertEq(adapter.totalAssetsManaged(), nav + 123e18, "idle token0 counted at par");
    }

    function test_TotalAssets_ZeroWhenNoPosition() public view {
        assertEq(adapter.totalAssetsManaged(), 0, "no position, no idle -> zero NAV");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       WITHDRAW — SHORTFALL-HONEST
    //////////////////////////////////////////////////////////////////////////*//

    function test_Withdraw_FreesToken0_ShortfallHonest() public {
        _fund(1_000e18, 1_000e18);
        adapter.deploy();
        uint256 vault0Before = token0.balanceOf(vault);

        uint256 reported = adapter.withdraw(400e18, vault);
        // Honest real delta: the reported value EQUALS the actual token0 the vault received.
        uint256 vault0Delta = token0.balanceOf(vault) - vault0Before;
        assertEq(reported, vault0Delta, "reports exactly the real token0 delta to vault");
        assertGt(reported, 0, "freed some token0");
        // Two-token caveat: a full-range decrease frees token0 AND token1 in the pool ratio, so the
        // token0 freed for a 400-token0 ask is ~half (the rest comes out as token1, also sent to vault).
        assertGt(token1.balanceOf(vault), 0, "freed token1 routed to vault too");
        assertLe(reported, 400e18, "never over-reports the requested token0");
    }

    function test_Withdraw_NeverOverReports_WholePosition() public {
        _fund(1_000e18, 1_000e18);
        adapter.deploy();
        uint256 nav = adapter.totalAssetsManaged(); // ~2000 token0-value
        uint256 vault0Before = token0.balanceOf(vault);

        // Ask for far more than the whole position; adapter removes ALL liquidity.
        uint256 reported = adapter.withdraw(nav * 2, vault);
        uint256 vault0Delta = token0.balanceOf(vault) - vault0Before;
        assertEq(reported, vault0Delta, "reported == real token0 delta");
        // The whole position is gone; remaining NAV is ~0 (only any dust).
        assertLt(adapter.totalAssetsManaged(), 1e12, "position fully removed");
        // token0 freed is ~1000 (its half of the position); honest, not the 2000 token0-value asked.
        assertApproxEqRel(reported, 1_000e18, 1e15, "honest token0 freed ~ position's token0 leg");
    }

    function test_Withdraw_RevertsZeroRecipient() public {
        _fund(1_000e18, 1_000e18);
        adapter.deploy();
        // The recipient is now pinned to the adapter's vault, so any non-vault recipient (incl. the
        // zero address) is rejected with ProtocolAdapterInvalidRecipient.
        vm.expectRevert(abi.encodeWithSelector(IProtocolAdapter.ProtocolAdapterInvalidRecipient.selector, address(0)));
        adapter.withdraw(100e18, address(0));
    }

    function test_Withdraw_ZeroWhenNoPosition() public {
        assertEq(adapter.withdraw(100e18, vault), 0, "no position -> withdraws 0");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 HARVEST
    //////////////////////////////////////////////////////////////////////////*//

    function test_Harvest_CollectsAndForwardsFeesRaw_NoNavInflation() public {
        _fund(1_000e18, 1_000e18);
        adapter.deploy();
        uint256 navBefore = adapter.totalAssetsManaged();

        // Accrue swap fees in both tokens, claimable via collect.
        npm.accrueFees(adapter.tokenId(), 7e18, 9e18);
        // Fees are NOT in NAV (principal liquidity unchanged) — proven before harvesting.
        assertEq(adapter.totalAssetsManaged(), navBefore, "uncollected fees not counted in NAV");

        // The adapter may hold <=1 wei of each token as deploy rounding dust; harvest forwards the
        // collected fees RAW *plus* that dust (it sweeps the full balance). Account for it honestly.
        uint256 dust0 = token0.balanceOf(address(adapter));
        uint256 dust1 = token1.balanceOf(address(adapter));
        adapter.harvest();
        assertEq(token0.balanceOf(treasury), 7e18 + dust0, "fee0 (+dust) forwarded raw to recipient");
        assertEq(token1.balanceOf(treasury), 9e18 + dust1, "fee1 (+dust) forwarded raw to recipient");
        // Harvest does not touch the LP PRINCIPAL: the position's liquidity is untouched, so NAV only
        // drops by the idle-token0 dust harvest swept out (the position-value component is unchanged).
        assertEq(adapter.totalAssetsManaged(), navBefore - dust0, "only idle-token0 dust left NAV; principal intact");
        assertEq(token0.balanceOf(address(adapter)), 0, "no token0 stranded");
        assertEq(token1.balanceOf(address(adapter)), 0, "no token1 stranded");
    }

    function test_Harvest_ZeroFees_Graceful() public {
        _fund(1_000e18, 1_000e18);
        adapter.deploy();
        adapter.harvest(); // no fees accrued -> must not revert
        // Only the <=1 wei deploy dust can reach the treasury; no principal is ever forwarded.
        assertLe(token0.balanceOf(treasury), 1, "no principal token0 forwarded");
        assertLe(token1.balanceOf(treasury), 1, "no principal token1 forwarded");
    }

    function test_Harvest_NoPosition_NoOp() public {
        adapter.harvest(); // no position minted -> graceful no-op
        assertEq(token0.balanceOf(treasury), 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            EMERGENCY WITHDRAW
    //////////////////////////////////////////////////////////////////////////*//

    function test_EmergencyWithdraw_FullExit_BothTokensToVault() public {
        _fund(1_000e18, 1_000e18);
        adapter.deploy();
        vm.prank(admin);
        uint256 recovered = adapter.emergencyWithdraw();
        assertGt(recovered, 0, "recovered token0 to vault");
        // Both tokens went to the vault; position fully closed.
        assertGt(token0.balanceOf(vault), 0, "vault got token0");
        assertGt(token1.balanceOf(vault), 0, "vault got token1");
        assertEq(adapter.totalAssetsManaged(), 0, "position fully closed");
        assertEq(token0.balanceOf(address(adapter)), 0, "adapter emptied of token0");
        assertEq(token1.balanceOf(address(adapter)), 0, "adapter emptied of token1");
    }

    function test_EmergencyWithdraw_WorksWhenStopped() public {
        _fund(1_000e18, 1_000e18);
        adapter.deploy();
        vm.prank(guardian);
        adapter.emergencyStop("incident"); // emergency-stop must NOT block the emergency exit
        vm.prank(admin);
        uint256 recovered = adapter.emergencyWithdraw();
        assertGt(recovered, 0, "exits even when stopped");
        assertGt(token0.balanceOf(vault), 0);
    }

    function test_EmergencyWithdraw_AlsoCollectsFees() public {
        _fund(1_000e18, 1_000e18);
        adapter.deploy();
        npm.accrueFees(adapter.tokenId(), 5e18, 5e18);
        vm.prank(admin);
        adapter.emergencyWithdraw();
        // Emergency sweeps principal + fees (indistinguishable once collected) to the vault.
        assertGt(token1.balanceOf(vault), 1_000e18, "vault got token1 principal + fees");
    }

    function test_EmergencyWithdraw_OnlyAdmin() public {
        _fund(1_000e18, 1_000e18);
        adapter.deploy();
        vm.prank(address(0xBAD));
        vm.expectRevert(); // AccessControlUnauthorizedAccount
        adapter.emergencyWithdraw();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function test_Config_Getters() public view {
        assertEq(adapter.positionManager(), address(npm));
        assertEq(adapter.pool(), address(pool));
        assertEq(adapter.token0(), address(token0));
        assertEq(adapter.token1(), address(token1));
        assertEq(adapter.asset(), address(token0), "asset == token0");
        assertEq(adapter.fee(), FEE);
        assertEq(adapter.vault(), vault);
        assertEq(adapter.twapWindow(), TWAP_WINDOW);
        assertEq(adapter.slippageBps(), SLIPPAGE_BPS);
        assertEq(adapter.rewardRecipient(), treasury);
        assertEq(adapter.tokenId(), 0, "no position yet");
    }

    function test_SetTwapWindow_OnlyAdmin_NonZero() public {
        vm.prank(admin);
        adapter.setTwapWindow(3600);
        assertEq(adapter.twapWindow(), 3600);
        vm.prank(admin);
        vm.expectRevert(IUniswapV3Adapter.UniswapV3AdapterTwapWindowZero.selector);
        adapter.setTwapWindow(0);
    }

    function test_SetSlippage_OnlyAdmin_Bounded() public {
        vm.prank(admin);
        adapter.setSlippageBps(250);
        assertEq(adapter.slippageBps(), 250);
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IUniswapV3Adapter.UniswapV3AdapterSlippageTooHigh.selector, 10_001, 10_000)
        );
        adapter.setSlippageBps(10_001);
    }

    function test_SetRewardRecipient_OnlyAdmin_NonZero() public {
        vm.prank(admin);
        adapter.setRewardRecipient(address(0xCAFE));
        assertEq(adapter.rewardRecipient(), address(0xCAFE));
        vm.prank(admin);
        vm.expectRevert(IProtocolAdapter.ProtocolAdapterZeroAddress.selector);
        adapter.setRewardRecipient(address(0));
    }

    function test_Config_OnlyAdminGuards() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        adapter.setSlippageBps(50);
    }

    function test_IsPaused_ReflectsState() public {
        assertEq(adapter.isPaused(), false);
        vm.prank(admin);
        adapter.pause();
        assertEq(adapter.isPaused(), true);
    }

    function test_HealthFactor_NoDebt() public view {
        assertEq(adapter.healthFactor(), type(uint256).max);
        assertEq(adapter.minHealthFactor(), type(uint256).max);
    }

    function test_SupportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IUniswapV3Adapter).interfaceId), "IUniswapV3Adapter");
        assertTrue(adapter.supportsInterface(type(IProtocolAdapter).interfaceId), "IProtocolAdapter");
    }

    function test_OnERC721Received_ReturnsSelector() public {
        assertEq(
            adapter.onERC721Received(address(0), address(0), 1, ""),
            bytes4(0x150b7a02),
            "returns the IERC721Receiver magic value"
        );
    }
}
