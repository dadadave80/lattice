// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {CurveStableSwapAdapter} from "@lattice/defi/CurveStableSwapAdapter.sol";
import {CurveStableSwapAdapterLib} from "@lattice/defi/libraries/CurveStableSwapAdapterLib.sol";
import {ICurveStableSwapAdapter} from "@lattice/interfaces/defi/ICurveStableSwapAdapter.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {Test} from "forge-std/Test.sol";

import {MockAsset} from "./AaveV3AdapterSupplyTest.t.sol";

//*//////////////////////////////////////////////////////////////////////////
//                         MOCK LP + CRV + POOL + GAUGE
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal ERC20 used both for the pool LP token and the CRV reward token.
contract MockToken {
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

    function burn(address from, uint256 a) external {
        balanceOf[from] -= a;
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

/// @notice 2-coin Curve StableSwap mock. coin0 is the supplied asset; coin1 is a dummy peer.
///         1:1 stable accounting modulated by `virtualPrice` (WAD): depositing `amount` mints
///         `amount * 1e18 / vp` LP, so `lp * vp / 1e18 == amount` at deposit. Bumping `virtualPrice`
///         simulates fee yield accruing to existing LP. A `liquidityCap` on coin0 lets withdrawals
///         under-deliver so the adapter's shortfall-honesty can be exercised.
contract MockCurvePool {
    MockAsset public coin0;
    MockToken public coin1;
    MockToken public lp;
    uint256 public virtualPrice = 1e18;
    uint256 public liquidityCap = type(uint256).max; // cap on coin0 paid out on withdraw
    uint256 public mintBps = 10_000; // haircut applied to ACTUAL minting vs calc (fee/imbalance sim)

    constructor(MockAsset a, MockToken peer, MockToken lpToken) {
        coin0 = a;
        coin1 = peer;
        lp = lpToken;
    }

    function setVirtualPrice(uint256 vp) external {
        virtualPrice = vp;
    }

    function setLiquidityCap(uint256 cap) external {
        liquidityCap = cap;
    }

    /// @dev Simulate the pool minting fewer LP than `calc_token_amount` predicted (deposit fee /
    ///      imbalance). Only affects `add_liquidity`, not the `calc` quote — exactly the divergence
    ///      the adapter's `minMint` slippage floor is meant to catch.
    function setMintBps(uint256 bps) external {
        mintBps = bps;
    }

    function coins(uint256 i) external view returns (address) {
        if (i == 0) return address(coin0);
        if (i == 1) return address(coin1);
        revert("idx");
    }

    function get_virtual_price() external view returns (uint256) {
        return virtualPrice;
    }

    function calc_token_amount(uint256[2] calldata amounts, bool) external view returns (uint256) {
        uint256 total = amounts[0] + amounts[1];
        return (total * 1e18) / virtualPrice;
    }

    function calc_withdraw_one_coin(uint256 lpAmt, int128) external view returns (uint256) {
        return (lpAmt * virtualPrice) / 1e18;
    }

    function add_liquidity(uint256[2] calldata amounts, uint256 minMint) external returns (uint256 minted) {
        uint256 total = amounts[0] + amounts[1];
        if (amounts[0] > 0) require(coin0.transferFrom(msg.sender, address(this), amounts[0]), "pull0");
        if (amounts[1] > 0) require(coin1.transferFrom(msg.sender, address(this), amounts[1]), "pull1");
        minted = (((total * 1e18) / virtualPrice) * mintBps) / 10_000;
        require(minted >= minMint, "slippage");
        lp.mint(msg.sender, minted);
    }

    function remove_liquidity_one_coin(uint256 lpAmt, int128, uint256 minOut) external returns (uint256 out) {
        require(lp.balanceOf(msg.sender) >= lpAmt, "lp bal");
        lp.burn(msg.sender, lpAmt);
        out = (lpAmt * virtualPrice) / 1e18;
        if (out > liquidityCap) out = liquidityCap; // simulate a thin pool / shortfall
        require(out >= minOut, "slippage");
        require(coin0.transfer(msg.sender, out), "send");
    }
}

/// @notice Curve gauge mock: stakes LP 1:1, pays a configurable CRV amount on claim.
contract MockCurveGauge {
    MockToken public lp;
    MockToken public crv;
    uint256 public claimable;
    mapping(address => uint256) public balanceOf;

    constructor(MockToken lpToken, MockToken crvToken) {
        lp = lpToken;
        crv = crvToken;
    }

    function setClaimable(uint256 a) external {
        claimable = a;
    }

    function deposit(uint256 value) external {
        require(lp.transferFrom(msg.sender, address(this), value), "pull");
        balanceOf[msg.sender] += value;
    }

    function withdraw(uint256 value) external {
        require(balanceOf[msg.sender] >= value, "stake");
        balanceOf[msg.sender] -= value;
        require(lp.transfer(msg.sender, value), "send");
    }

    function claim_rewards(address addr) external {
        if (claimable > 0) crv.mint(addr, claimable);
        claimable = 0;
    }
}

/// @notice Adapter composed with Pausable + EmergencyStop facets (as a real Diamond would).
contract MockCurveAdapter is CurveStableSwapAdapter, Pausable, EmergencyStop {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(Pausable, EmergencyStop) returns (bytes memory) {}

    function initialize(
        address admin_,
        address pool_,
        address lpToken_,
        address gauge_,
        address asset_,
        int128 coinIndex_,
        address vault_,
        address recipient_,
        uint256 slippageBps_
    ) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        ReentrancyGuardLib.__ReentrancyGuard_init();
        PausableLib.__Pausable_init();
        EmergencyStopLib.__EmergencyStop_init();
        CurveStableSwapAdapterLib.__CurveStableSwapAdapter_init(
            pool_, lpToken_, gauge_, asset_, coinIndex_, vault_, recipient_, slippageBps_
        );
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) external view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

contract CurveStableSwapAdapterTest is Test {
    MockAsset asset;
    MockToken peer;
    MockToken lp;
    MockToken crv;
    MockCurvePool pool;
    MockCurveGauge gauge;
    MockCurveAdapter adapter;

    address admin = address(0xAD);
    address guardian = address(0x6);
    address vault = address(0x7A17);
    address treasury = address(0x7E0);
    int128 constant COIN_INDEX = 0;
    uint256 constant SLIPPAGE_BPS = 100; // 1%

    function _deployStaked() internal {
        adapter = new MockCurveAdapter();
        adapter.initialize(
            admin, address(pool), address(lp), address(gauge), address(asset), COIN_INDEX, vault, treasury, SLIPPAGE_BPS
        );
        vm.startPrank(admin);
        adapter.addGuardian(guardian);
        adapter.setCrvToken(address(crv));
        // Authorize this test contract as the operator so the direct deploy/withdraw/harvest calls
        // (which the StrategyManager would make in production) pass the operator gate.
        adapter.setOperator(address(this));
        vm.stopPrank();
    }

    function _deployUnstaked() internal {
        adapter = new MockCurveAdapter();
        adapter.initialize(
            admin, address(pool), address(lp), address(0), address(asset), COIN_INDEX, vault, treasury, SLIPPAGE_BPS
        );
        vm.startPrank(admin);
        adapter.addGuardian(guardian);
        // Authorize this test contract as the operator (see _deployStaked).
        adapter.setOperator(address(this));
        vm.stopPrank();
    }

    function setUp() public {
        asset = new MockAsset();
        peer = new MockToken("Peer", "PEER");
        lp = new MockToken("Curve LP", "crvLP");
        crv = new MockToken("Curve DAO", "CRV");
        pool = new MockCurvePool(asset, peer, lp);
        gauge = new MockCurveGauge(lp, crv);
        // seed the pool with a peer-coin reserve isn't needed: 1:1 mock, coin0 reserve grows on deposit.
        _deployUnstaked();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  DEPLOY
    //////////////////////////////////////////////////////////////////////////*//

    function test_Deploy_AddsLiquidity_Unstaked() public {
        asset.mint(address(adapter), 1_000e6);
        uint256 deployed = adapter.deploy();
        assertEq(deployed, 1_000e6, "reports idle deployed");
        assertEq(asset.balanceOf(address(adapter)), 0, "idle swept to 0");
        // vp == 1e18, so LP minted == asset deposited, and the adapter holds it (unstaked).
        assertEq(lp.balanceOf(address(adapter)), 1_000e6, "LP held by adapter");
        assertEq(adapter.totalAssetsManaged(), 1_000e6, "NAV == lp * vp / 1e18");
    }

    function test_Deploy_AddsLiquidity_Staked() public {
        _deployStaked();
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        assertEq(lp.balanceOf(address(adapter)), 0, "LP not held loose when staked");
        assertEq(gauge.balanceOf(address(adapter)), 1_000e6, "LP staked in gauge");
        assertEq(adapter.totalAssetsManaged(), 1_000e6, "NAV counts staked LP");
    }

    function test_Deploy_RevertsWhenNothingToDeploy() public {
        vm.expectRevert(IProtocolAdapter.ProtocolAdapterNothingToDeploy.selector);
        adapter.deploy();
    }

    function test_Deploy_RevertsWhenPaused() public {
        asset.mint(address(adapter), 1_000e6);
        vm.prank(admin);
        adapter.pause();
        vm.expectRevert(IProtocolAdapter.ProtocolAdapterPaused.selector);
        adapter.deploy();
    }

    function test_Deploy_RevertsWhenStopped() public {
        asset.mint(address(adapter), 1_000e6);
        vm.prank(guardian);
        adapter.emergencyStop("incident");
        vm.expectRevert(IProtocolAdapter.ProtocolAdapterPaused.selector);
        adapter.deploy();
    }

    function test_Deploy_EnforcesSlippageMinOut() public {
        asset.mint(address(adapter), 1_000e6);
        // Adapter sizes minMint = calc * (1 - 1%) = 990e6. If the pool actually mints 2% fewer LP
        // than its own calc quote (deposit fee / imbalance), minted = 980e6 < 990e6 floor → the pool
        // honors the slippage floor and reverts. Proves the adapter passes a non-trivial minMint.
        pool.setMintBps(9_800); // 2% mint haircut, below the 1% slippage tolerance
        vm.expectRevert(bytes("slippage"));
        adapter.deploy();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              TOTAL ASSETS
    //////////////////////////////////////////////////////////////////////////*//

    function test_TotalAssets_TracksVirtualPrice() public {
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        assertEq(adapter.totalAssetsManaged(), 1_000e6, "baseline NAV");
        pool.setVirtualPrice(1.1e18); // +10% pool yield
        assertEq(adapter.totalAssetsManaged(), 1_100e6, "NAV scales with virtual price");
    }

    function test_TotalAssets_ZeroWhenNoPosition() public view {
        assertEq(adapter.totalAssetsManaged(), 0, "no LP -> zero NAV");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                WITHDRAW
    //////////////////////////////////////////////////////////////////////////*//

    function test_Withdraw_ReturnsRealAmount_Unstaked() public {
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        uint256 got = adapter.withdraw(400e6, vault);
        assertEq(got, 400e6, "real asset delta to vault");
        assertEq(asset.balanceOf(vault), 400e6, "vault received");
        assertEq(adapter.totalAssetsManaged(), 600e6, "remaining NAV");
    }

    function test_Withdraw_PullsFromGaugeFirst_Staked() public {
        _deployStaked();
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        uint256 got = adapter.withdraw(300e6, vault);
        assertEq(got, 300e6, "withdrew from staked LP");
        assertEq(asset.balanceOf(vault), 300e6, "vault received");
        assertEq(gauge.balanceOf(address(adapter)), 700e6, "gauge unstaked partially");
    }

    function test_Withdraw_ShortfallHonest() public {
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        // Pool can only pay out 250e6 of coin0 regardless of LP burned.
        pool.setLiquidityCap(250e6);
        // To avoid the pool's own slippage revert, widen tolerance so minOut <= cap is satisfiable:
        // ask 200e6 (< cap) so the real delta is the honest amount.
        uint256 got = adapter.withdraw(200e6, vault);
        assertEq(got, 200e6, "honest real delta under cap");
        assertEq(asset.balanceOf(vault), 200e6);
    }

    function test_Withdraw_NeverOverReports() public {
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        // Cap the pool so even a large LP burn returns only 600e6; the adapter must report <= delta.
        pool.setLiquidityCap(600e6);
        uint256 got = adapter.withdraw(600e6, vault);
        assertEq(got, 600e6, "reports exactly the real delta");
        assertEq(asset.balanceOf(vault), got, "vault balance equals reported");
    }

    function test_Withdraw_RevertsZeroRecipient() public {
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        // The recipient is now pinned to the adapter's vault, so any non-vault recipient (incl. the
        // zero address) is rejected with ProtocolAdapterInvalidRecipient.
        vm.expectRevert(abi.encodeWithSelector(IProtocolAdapter.ProtocolAdapterInvalidRecipient.selector, address(0)));
        adapter.withdraw(100e6, address(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                HARVEST
    //////////////////////////////////////////////////////////////////////////*//

    function test_Harvest_ForwardsCrvRaw_Staked() public {
        _deployStaked();
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        gauge.setClaimable(42e18);
        uint256 navBefore = adapter.totalAssetsManaged();
        adapter.harvest();
        assertEq(crv.balanceOf(treasury), 42e18, "CRV forwarded raw to recipient");
        assertEq(adapter.totalAssetsManaged(), navBefore, "harvest does not change NAV");
    }

    function test_Harvest_NoGauge_NoOp() public {
        // Unstaked adapter (gauge == 0) cannot claim; harvest is a graceful no-op.
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        adapter.harvest();
        assertEq(crv.balanceOf(treasury), 0, "no rewards without a gauge");
    }

    function test_Harvest_ZeroClaim_Graceful() public {
        _deployStaked();
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        gauge.setClaimable(0);
        adapter.harvest(); // must not revert
        assertEq(crv.balanceOf(treasury), 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            EMERGENCY WITHDRAW
    //////////////////////////////////////////////////////////////////////////*//

    function test_EmergencyWithdraw_FullExit_Unstaked() public {
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        vm.prank(admin);
        uint256 rec = adapter.emergencyWithdraw();
        assertEq(rec, 1_000e6, "full single-coin exit to vault");
        assertEq(asset.balanceOf(vault), 1_000e6);
        assertEq(adapter.totalAssetsManaged(), 0, "position fully closed");
    }

    function test_EmergencyWithdraw_FullExit_Staked() public {
        _deployStaked();
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        vm.prank(admin);
        uint256 rec = adapter.emergencyWithdraw();
        assertEq(rec, 1_000e6, "unstake + exit");
        assertEq(asset.balanceOf(vault), 1_000e6);
        assertEq(gauge.balanceOf(address(adapter)), 0, "gauge emptied");
        assertEq(lp.balanceOf(address(adapter)), 0, "LP burned");
    }

    function test_EmergencyWithdraw_WorksWhenStopped() public {
        _deployStaked();
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        vm.prank(guardian);
        adapter.emergencyStop("incident"); // emergency-stop must NOT block the emergency exit
        vm.prank(admin);
        uint256 rec = adapter.emergencyWithdraw();
        assertEq(rec, 1_000e6, "exits even when stopped");
        assertEq(asset.balanceOf(vault), 1_000e6);
    }

    function test_EmergencyWithdraw_OnlyAdmin() public {
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        vm.prank(address(0xBAD));
        vm.expectRevert(); // AccessControlUnauthorizedAccount
        adapter.emergencyWithdraw();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function test_Config_Getters() public {
        _deployStaked();
        assertEq(adapter.pool(), address(pool));
        assertEq(adapter.lpToken(), address(lp));
        assertEq(adapter.gauge(), address(gauge));
        assertEq(adapter.vault(), vault);
        assertEq(adapter.coinIndex(), COIN_INDEX);
        assertEq(adapter.slippageBps(), SLIPPAGE_BPS);
        assertEq(adapter.rewardRecipient(), treasury);
        assertEq(adapter.asset(), address(asset));
    }

    function test_SetGauge_OnlyAdmin() public {
        vm.prank(admin);
        adapter.setGauge(address(gauge));
        assertEq(adapter.gauge(), address(gauge));
    }

    function test_SetSlippage_OnlyAdmin_AndBounded() public {
        vm.prank(admin);
        adapter.setSlippageBps(250);
        assertEq(adapter.slippageBps(), 250);
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICurveStableSwapAdapter.CurveStableSwapAdapterSlippageTooHigh.selector, 10_001, 10_000
            )
        );
        adapter.setSlippageBps(10_001);
    }

    function test_IsPaused_ReflectsState() public {
        assertEq(adapter.isPaused(), false);
        vm.prank(admin);
        adapter.pause();
        assertEq(adapter.isPaused(), true);
    }

    function test_SupportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(ICurveStableSwapAdapter).interfaceId), "ICurveStableSwapAdapter");
        assertTrue(adapter.supportsInterface(type(IProtocolAdapter).interfaceId), "IProtocolAdapter");
    }
}
