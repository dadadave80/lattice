// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StrategyManagerTestBase} from "@lattice-test/base/StrategyManagerTestBase.sol";
import {VaultCoreTestBase} from "@lattice-test/base/VaultCoreTestBase.sol";
import {IMintableToken} from "@lattice-test/helpers/IMintableToken.sol";
import {StrategyManager} from "@lattice/defi/StrategyManager.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {IStrategyManager} from "@lattice/interfaces/defi/IStrategyManager.sol";
import {IUniswapV3Adapter} from "@lattice/interfaces/defi/IUniswapV3Adapter.sol";
import {IVaultCore} from "@lattice/interfaces/defi/IVaultCore.sol";
import {IStrategy} from "@lattice/interfaces/external/yearn/IStrategy.sol";
import {UniswapV3FullRangeMath} from "@lattice/utils/libraries/UniswapV3FullRangeMath.sol";
import {Math} from "@lattice/utils/libraries/math/Math.sol";
import {Vm} from "forge-std/Vm.sol";

import {MockAToken, MockAaveAdapter, MockAaveV3Pool, MockAsset} from "./AaveV3AdapterSupplyTest.t.sol";
import {MockComet, MockCompoundAdapter} from "./CompoundV3AdapterTest.t.sol";
import {MockERC4626, MockERC4626Adapter} from "./ERC4626AdapterTest.t.sol";
import {MockLidoAdapter, MockLidoWithdrawalQueue, MockStETH, MockWETH, MockWstETH} from "./LidoAdapterTest.t.sol";
import {MockERC20, MockPositionManager, MockUniV3Adapter, MockUniV3Pool} from "./UniswapV3AdapterTest.t.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                   BASE
//////////////////////////////////////////////////////////////////////////*//

/// @title StrategyLiquidityTestBase
/// @notice Regression base for #221 on the production {DeployVaultCore} + {DeployStrategyManager} diamonds: each
///         suite wires one protocol adapter in as the manager's strategy (the adapter's operator is the manager
///         diamond, as in production) and drives `rebalance()` through recalls at non-integer exchange rates and
///         with undeployed idle.
abstract contract StrategyLiquidityTestBase is VaultCoreTestBase, StrategyManagerTestBase {
    address internal alice = address(0xA11CE);
    address internal treasury = address(0x7E0);

    /// @dev Total rounding slack for a rebalance's NAV movement across one recall plus one deploy.
    uint256 internal constant NAV_SLACK = 20;

    function setUp() public virtual override {}

    /// @dev Deploys the VaultCore + StrategyManager recipe diamonds over `asset_` and wires them together.
    function _wire(address asset_) internal {
        vaultAddr = _deployVault(asset_, "Vault Share", "vSHARE", admin);
        vault = IVaultCore(vaultAddr);
        diamond = _deployStrategyManager(admin);
        mgr = StrategyManager(diamond);
        vm.startPrank(admin);
        vault.setStrategyManager(diamond);
        mgr.setVault(vaultAddr);
        vm.stopPrank();
    }

    function _addStrategy(address strategy, uint16 bps) internal {
        vm.prank(admin);
        mgr.addStrategy(strategy, bps);
    }

    function _setTarget(address strategy, uint16 bps) internal {
        vm.prank(admin);
        mgr.updateStrategyTarget(strategy, bps);
    }

    function _deposit(address asset_, uint256 assets) internal {
        IMintableToken(asset_).mint(alice, assets);
        vm.startPrank(alice);
        IMintableToken(asset_).approve(vaultAddr, assets);
        vault.deposit(assets, alice);
        vm.stopPrank();
    }

    /// @dev Rebalances and asserts the vault's NAV is conserved and the strategy ends at its target.
    function _rebalanceToTarget(address strategy, uint16 bps) internal {
        uint256 navBefore = vault.totalAssets();
        mgr.rebalance();
        assertApproxEqAbs(vault.totalAssets(), navBefore, NAV_SLACK, "rebalance conserves NAV");
        assertApproxEqAbs(
            IStrategy(strategy).totalAssetsManaged(), (navBefore * bps) / 10_000, NAV_SLACK, "strategy at target"
        );
    }

    /// @dev Like {_rebalanceToTarget}, and asserts the recall spent `strategy`'s idle before its position: the
    ///      rebalance's deploy pass found no idle left to deploy. (A position-only recall would leave the idle
    ///      behind for the deploy pass to sweep, ending in the same balances.)
    function _rebalanceToTargetSpendingIdle(address strategy, uint16 bps) internal {
        vm.recordLogs();
        _rebalanceToTarget(strategy, bps);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == strategy) {
                assertTrue(logs[i].topics[0] != IProtocolAdapter.Deployed.selector, "idle spent by the recall");
            }
        }
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                      ERC4626 ADAPTER (ISSUE POC a/b/c)
//////////////////////////////////////////////////////////////////////////*//

/// @notice The issue's three proof-of-concept scenarios on the ERC4626 adapter: (a) a recall at a 1.066666 price
///         per share, (b) a recall of undeployed idle after the target drops from 50% to 10%, and (c) the 1:1
///         control recall.
contract ERC4626StrategyLiquidityTest is StrategyLiquidityTestBase {
    MockAsset internal asset;
    MockERC4626 internal target;
    MockERC4626Adapter internal adapter;

    function setUp() public override {
        asset = new MockAsset();
        target = new MockERC4626(asset);
        _wire(address(asset));

        adapter = new MockERC4626Adapter();
        adapter.initialize(admin, address(target), address(asset), vaultAddr, treasury);
        vm.prank(admin);
        adapter.setOperator(diamond);
        _addStrategy(address(adapter), 5_000);

        _deposit(address(asset), 1_000e6);
    }

    /// @dev Allocates 50% and makes sure it ends up deployed in the target vault.
    function _allocateAndDeploy() internal {
        mgr.rebalance();
        if (asset.balanceOf(address(adapter)) > 0) {
            vm.prank(diamond);
            adapter.deploy();
        }
        assertEq(target.balanceOf(address(adapter)), 500e6, "500 shares at 1:1");
    }

    /// @notice PoC (a): after target-vault yield moves the price per share to 1.066666, the recall of the
    ///         16,666,500 excess delivers exactly. Before #221 it reverted with `StrategyManagerWithdrawShortfall`.
    function test_PoC_a_NonIntegerRate_RecallSucceeds() public {
        _allocateAndDeploy();
        target.accrueYield(33_333_000); // 500e6 shares: price per share 1.066666
        assertEq(adapter.totalAssetsManaged(), 533_333_000, "position marked up");

        uint256 idleBefore = vault.idleAssets();
        _rebalanceToTarget(address(adapter), 5_000);
        assertEq(vault.idleAssets() - idleBefore, 16_666_500, "exact excess recalled");
    }

    /// @notice PoC (b): with the allocation still idle in the adapter (the target vault refuses deposits), the
    ///         target drops from 50% to 10% and the 400e6 recall is paid from idle. Before #221 it reverted with
    ///         `StrategyManagerWithdrawShortfall(adapter, 400e6, 0)`.
    function test_PoC_b_UndeployedIdle_RecallSucceeds() public {
        target.setDepositsBlocked(true);
        mgr.rebalance();
        assertEq(asset.balanceOf(address(adapter)), 500e6, "allocation left undeployed");

        _setTarget(address(adapter), 1_000);
        _rebalanceToTarget(address(adapter), 1_000);
        assertEq(vault.idleAssets(), 900e6, "400e6 recalled from the adapter's idle");
    }

    /// @notice PoC (c): the 1:1 control recall succeeds, unchanged.
    function test_PoC_c_OneToOne_RecallSucceeds() public {
        _allocateAndDeploy();
        _setTarget(address(adapter), 1_000);
        _rebalanceToTarget(address(adapter), 1_000);
        assertEq(vault.idleAssets(), 900e6, "400e6 recalled");
    }

    /// @notice #221: `rebalance()` deploys the adapter's allocation itself, so allocated funds do not sit idle.
    function test_Rebalance_DeploysAllocation() public {
        mgr.rebalance();
        assertEq(asset.balanceOf(address(adapter)), 0, "no idle left in the adapter");
        assertEq(target.balanceOf(address(adapter)), 500e6, "allocation deployed into the target vault");
        assertEq(adapter.totalAssetsManaged(), 500e6, "NAV unchanged by the deploy");
    }

    /// @notice #221: a target vault that refuses deposits leaves the allocation idle without reverting, and
    ///         reports the failed deploy.
    function test_Rebalance_FailedDeploy_ReportedNotReverted() public {
        target.setDepositsBlocked(true);
        vm.expectEmit(true, false, false, false, diamond);
        emit IStrategyManager.StrategyDeployFailed(address(adapter), "");
        mgr.rebalance();
        assertEq(adapter.totalAssetsManaged(), 500e6, "allocation counted while idle");
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                              AAVE V3 ADAPTER
//////////////////////////////////////////////////////////////////////////*//

contract AaveStrategyLiquidityTest is StrategyLiquidityTestBase {
    MockAsset internal asset;
    MockAToken internal aToken;
    MockAaveV3Pool internal pool;
    MockAaveAdapter internal adapter;

    function setUp() public override {
        asset = new MockAsset();
        aToken = new MockAToken(asset);
        pool = new MockAaveV3Pool();
        pool.setAToken(asset, aToken);
        _wire(address(asset));

        adapter = new MockAaveAdapter();
        adapter.initialize(admin, address(pool), address(asset), vaultAddr, treasury, keccak256("USDC/USD"), 1.05e18);
        vm.prank(admin);
        adapter.setOperator(diamond);
        _addStrategy(address(adapter), 5_000);

        _deposit(address(asset), 1_000e6);
        mgr.rebalance();
        assertEq(aToken.balanceOf(address(adapter)), 500e6, "allocation supplied by rebalance");
    }

    /// @notice #221: after interest leaves the aToken balance at a non-round figure, and with undeployed idle
    ///         on top, lowering the target recalls the excess (idle first) without reverting.
    function test_Recall_AfterAccrual_WithIdle() public {
        aToken.mint(address(adapter), 7_777_777); // accrued interest
        pool.addLiquidity(7_777_777);
        asset.mint(address(adapter), 33_333_333); // undeployed idle
        _setTarget(address(adapter), 2_000);
        _rebalanceToTargetSpendingIdle(address(adapter), 2_000);
        assertEq(asset.balanceOf(address(adapter)), 0, "no idle left behind");
    }

    address internal borrower = address(0xB0B);

    /// @dev A borrower takes `amount` of the reserve's cash (a utilisation spike).
    function _borrowOut(uint256 amount) internal {
        vm.prank(borrower);
        pool.borrow(address(asset), amount, 2, 0, borrower);
    }

    /// @dev The borrower repays everything, refilling the reserve's cash.
    function _repayAll() internal {
        uint256 owed = pool.debt(borrower);
        vm.startPrank(borrower);
        asset.approve(address(pool), owed);
        pool.repay(address(asset), owed, 2, borrower);
        vm.stopPrank();
    }

    /// @notice #271: the reserve holds only 100 of the 300 a lower target recalls. The recall takes the available
    ///         cash, rebalance completes as an honest partial recall, and the next rebalance finishes it once the
    ///         cash is back.
    function test_Recall_UtilisationSpike_IsPartial_ThenCompletes() public {
        _borrowOut(400e6); // cash 500 → 100
        _setTarget(address(adapter), 2_000);
        uint256 nav = vault.totalAssets();

        vm.expectEmit(true, false, false, true, diamond);
        emit IStrategyManager.StrategyPartiallyRecalled(address(adapter), 300e6, 100e6);
        mgr.rebalance();
        assertEq(vault.totalAssets(), nav, "partial recall conserves NAV");
        assertEq(vault.idleAssets(), 600e6, "recalled the available cash");
        assertEq(adapter.totalAssetsManaged(), 400e6, "remainder still supplied");

        _repayAll();
        _rebalanceToTarget(address(adapter), 2_000);
    }

    /// @notice #271: with the reserve's cash fully borrowed the recall takes nothing, and rebalance still completes.
    function test_Recall_NoCash_IsZeroPartial() public {
        _borrowOut(500e6);
        _setTarget(address(adapter), 2_000);

        vm.expectEmit(true, false, false, true, diamond);
        emit IStrategyManager.StrategyPartiallyRecalled(address(adapter), 300e6, 0);
        mgr.rebalance();
        assertEq(vault.totalAssets(), 1_000e6, "NAV unchanged");
        assertEq(adapter.totalAssetsManaged(), 500e6, "position untouched");
    }

    /// @notice #271: the adapter's idle is spent first, then the position up to the reserve's cash.
    function test_Recall_IdleThenShortCash() public {
        asset.mint(address(adapter), 50e6); // undeployed idle
        _borrowOut(400e6); // cash 500 → 100
        _setTarget(address(adapter), 2_000);
        uint256 nav = vault.totalAssets(); // 1_050e6
        uint256 requested = adapter.totalAssetsManaged() - (nav * 2_000) / 10_000;

        vm.expectEmit(true, false, false, true, diamond);
        emit IStrategyManager.StrategyPartiallyRecalled(address(adapter), requested, 150e6);
        mgr.rebalance();
        assertEq(vault.totalAssets(), nav, "partial recall conserves NAV");
        assertEq(asset.balanceOf(address(adapter)), 0, "idle spent first");
        assertEq(aToken.balanceOf(address(adapter)), 400e6, "then the reserve's cash");
    }

    /// @notice #271 on Aave v3.1+: the Pool pays out only up to its virtual balance, which a direct transfer to the
    ///         aToken does not raise. With the cash borrowed out and a donation on the aToken, the recall is capped
    ///         at the virtual balance (zero) instead of asking for the donated amount and reverting.
    function test_Recall_VirtualAccounting_DonationDoesNotLiftCap() public {
        pool.enableVirtualAccounting();
        _borrowOut(500e6);
        asset.mint(address(aToken), 10e6); // donation: real cash 10, virtual balance 0
        _setTarget(address(adapter), 2_000);

        vm.expectEmit(true, false, false, true, diamond);
        emit IStrategyManager.StrategyPartiallyRecalled(address(adapter), 300e6, 0);
        mgr.rebalance();
        assertEq(adapter.totalAssetsManaged(), 500e6, "position untouched");
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                            COMPOUND V3 ADAPTER
//////////////////////////////////////////////////////////////////////////*//

contract CompoundStrategyLiquidityTest is StrategyLiquidityTestBase {
    MockAsset internal asset;
    MockComet internal comet;
    MockCompoundAdapter internal adapter;

    function setUp() public override {
        asset = new MockAsset();
        comet = new MockComet(asset);
        _wire(address(asset));

        adapter = new MockCompoundAdapter();
        adapter.initialize(admin, address(comet), address(asset), vaultAddr, treasury);
        vm.prank(admin);
        adapter.setOperator(diamond);
        _addStrategy(address(adapter), 5_000);

        _deposit(address(asset), 1_000e6);
        mgr.rebalance();
        assertEq(comet.balanceOf(address(adapter)), 500e6, "allocation supplied by rebalance");
    }

    /// @notice #221: after interest leaves the Comet balance at a non-round figure, and with undeployed idle on
    ///         top, lowering the target recalls the excess (idle first) without reverting.
    function test_Recall_AfterAccrual_WithIdle() public {
        comet.accrueYield(address(adapter), 7_777_777);
        asset.mint(address(adapter), 33_333_333); // undeployed idle
        _setTarget(address(adapter), 2_000);
        _rebalanceToTargetSpendingIdle(address(adapter), 2_000);
        assertEq(asset.balanceOf(address(adapter)), 0, "no idle left behind");
    }

    address internal borrower = address(0xB0B);

    /// @notice #271: the market holds only 100 of the 300 a lower target recalls. The recall takes the available
    ///         cash, rebalance completes as an honest partial recall, and the next rebalance finishes it once the
    ///         cash is back.
    function test_Recall_UtilisationSpike_IsPartial_ThenCompletes() public {
        comet.borrow(borrower, 400e6); // cash 500 → 100
        _setTarget(address(adapter), 2_000);
        uint256 nav = vault.totalAssets();

        vm.expectEmit(true, false, false, true, diamond);
        emit IStrategyManager.StrategyPartiallyRecalled(address(adapter), 300e6, 100e6);
        mgr.rebalance();
        assertEq(vault.totalAssets(), nav, "partial recall conserves NAV");
        assertEq(vault.idleAssets(), 600e6, "recalled the available cash");
        assertEq(adapter.totalAssetsManaged(), 400e6, "remainder still supplied");

        asset.mint(address(comet), 400e6); // the borrower repays
        _rebalanceToTarget(address(adapter), 2_000);
    }

    /// @notice #271: with the market's cash fully borrowed the recall takes nothing, and rebalance still completes.
    function test_Recall_NoCash_IsZeroPartial() public {
        comet.borrow(borrower, 500e6);
        _setTarget(address(adapter), 2_000);

        vm.expectEmit(true, false, false, true, diamond);
        emit IStrategyManager.StrategyPartiallyRecalled(address(adapter), 300e6, 0);
        mgr.rebalance();
        assertEq(vault.totalAssets(), 1_000e6, "NAV unchanged");
        assertEq(adapter.totalAssetsManaged(), 500e6, "position untouched");
    }

    /// @notice #271: the adapter's idle is spent first, then the position up to the market's cash.
    function test_Recall_IdleThenShortCash() public {
        asset.mint(address(adapter), 50e6); // undeployed idle
        comet.borrow(borrower, 400e6); // cash 500 → 100
        _setTarget(address(adapter), 2_000);
        uint256 nav = vault.totalAssets(); // 1_050e6
        uint256 requested = adapter.totalAssetsManaged() - (nav * 2_000) / 10_000;

        vm.expectEmit(true, false, false, true, diamond);
        emit IStrategyManager.StrategyPartiallyRecalled(address(adapter), requested, 150e6);
        mgr.rebalance();
        assertEq(vault.totalAssets(), nav, "partial recall conserves NAV");
        assertEq(asset.balanceOf(address(adapter)), 0, "idle spent first");
        assertEq(comet.balanceOf(address(adapter)), 400e6, "then the market's cash");
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                               LIDO ADAPTER
//////////////////////////////////////////////////////////////////////////*//

/// @notice Lido recalls only from its WETH buffer, so a recall of a staked position is partial: rebalance must
///         complete, report it, and finish the recall once the queue refills the buffer.
contract LidoStrategyLiquidityTest is StrategyLiquidityTestBase {
    MockWETH internal weth;
    MockStETH internal stETH;
    MockWstETH internal wstETH;
    MockLidoWithdrawalQueue internal queue;
    MockLidoAdapter internal adapter;

    function setUp() public override {
        weth = new MockWETH();
        stETH = new MockStETH();
        wstETH = new MockWstETH(stETH);
        queue = new MockLidoWithdrawalQueue(stETH);
        vm.deal(address(queue), 1_000_000 ether);
        wstETH.setRate(1.1e18); // non-integer stETH per wstETH
        _wire(address(weth));

        adapter = new MockLidoAdapter();
        adapter.initialize(admin, address(weth), address(stETH), address(wstETH), address(queue), vaultAddr, treasury);
        vm.prank(admin);
        adapter.setOperator(diamond);
        _addStrategy(address(adapter), 5_000);

        // WETH backed 1:1 by ETH so the deploy's unwrap can pay out.
        vm.deal(address(weth), 100 ether);
        _deposit(address(weth), 100 ether);
        mgr.rebalance();
        assertEq(weth.balanceOf(address(adapter)), 0, "allocation staked by rebalance");
        assertGt(wstETH.balanceOf(address(adapter)), 0, "wstETH held");
    }

    /// @notice #221: lowering the target with an empty buffer is a partial recall (nothing synchronous to pay),
    ///         not a revert; the keeper's queue exit then lets the next rebalance finish the recall.
    function test_StakedRecall_IsPartial_ThenCompletesAfterClaim() public {
        _setTarget(address(adapter), 2_000);
        uint256 nav = vault.totalAssets();
        uint256 requested = adapter.totalAssetsManaged() - (nav * 2_000) / 10_000;

        vm.expectEmit(true, false, false, true, diamond);
        emit IStrategyManager.StrategyPartiallyRecalled(address(adapter), requested, 0);
        mgr.rebalance();
        assertApproxEqAbs(vault.totalAssets(), nav, NAV_SLACK, "partial recall conserves NAV");

        // Keeper exits part of the stake through the queue; the claim refills the WETH buffer.
        vm.startPrank(admin);
        uint256 id = adapter.requestWithdrawal(wstETH.balanceOf(address(adapter)) * 7 / 10);
        vm.stopPrank();
        adapter.claimWithdrawal(id);
        assertGt(weth.balanceOf(address(adapter)), requested, "buffer covers the recall");

        _rebalanceToTarget(address(adapter), 2_000);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                            UNISWAP V3 ADAPTER
//////////////////////////////////////////////////////////////////////////*//

/// @notice The swap-free UniswapV3 adapter's NAV is token0 only (#271): idle token0 plus the position's token0 leg
///         at the TWAP. Keeper-funded token1 and the position's token1 leg are never NAV, because the vault can only
///         ever receive token0. A recall pays from idle token0 and never unwinds the position (freeing its token0
///         leg would strand the token1 leg), so rebalance completes as a partial recall and the admin's
///         `emergencyWithdraw` is the only exit. A deploy priced at spot that would step NAV by more than
///         `slippageBps` of the token0 it consumes is refused.
contract UniswapV3StrategyLiquidityTest is StrategyLiquidityTestBase {
    MockERC20 internal token0;
    MockERC20 internal token1;
    MockUniV3Pool internal pool;
    MockPositionManager internal npm;
    MockUniV3Adapter internal adapter;

    int24 internal constant TWAP_TICK = 1234; // price ~1.1313 token1 per token0

    function setUp() public override {
        token0 = new MockERC20("Token0", "TK0");
        token1 = new MockERC20("Token1", "TK1");
        pool = new MockUniV3Pool(address(token0), address(token1), 3000, 60, TWAP_TICK);
        npm = new MockPositionManager(pool, token0, token1);
        _wire(address(token0));

        adapter = _newAdapter();
        _addStrategy(address(adapter), 5_000);

        _deposit(address(token0), 1_000e18);
        // The swap-free adapter cannot deploy token0 alone: the deploy fails, is reported, and leaves the
        // allocation idle (and counted).
        mgr.rebalance();
        assertEq(token0.balanceOf(address(adapter)), 500e18, "allocation idle until the keeper funds token1");
    }

    function _newAdapter() internal returns (MockUniV3Adapter a) {
        a = new MockUniV3Adapter();
        a.initialize(admin, address(npm), address(pool), vaultAddr, treasury, 1800, 100);
        vm.prank(admin);
        a.setOperator(diamond);
    }

    /// @dev token1 matching `amount0` at the TWAP price, plus 0.5% so token0 is the binding side.
    function _token1For(uint256 amount0) internal pure returns (uint256) {
        return _token1At(amount0, TWAP_TICK);
    }

    /// @dev token1 matching `amount0` at `tick`'s price, plus 0.5% so token0 is the binding side.
    function _token1At(uint256 amount0, int24 tick) internal pure returns (uint256) {
        uint160 sqrtP = UniswapV3FullRangeMath.getSqrtRatioAtTick(tick);
        uint256 a1 = Math.mulDiv(Math.mulDiv(amount0, sqrtP, 1 << 96), sqrtP, 1 << 96);
        return a1 + a1 / 200;
    }

    /// @dev Moves spot to `spotTick` (the TWAP stays at `TWAP_TICK`), funds `token1Amount` and runs the
    ///      permissionless `rebalance()`, whose deploy pass deploys the adapter's 500e18 idle token0 at spot.
    ///      Asserts the deploy was refused with {IUniswapV3Adapter.UniswapV3AdapterDeployOffTwap}, and that the
    ///      vault's NAV and the adapter's balances did not move.
    function _assertDeployRefusedAtSpot(int24 spotTick, uint256 token1Amount) internal {
        npm.setPayAtSpot(true);
        token1.mint(address(adapter), token1Amount);
        pool.setSpotTick(spotTick);
        uint256 nav = vault.totalAssets();

        vm.recordLogs();
        mgr.rebalance();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool refused;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == diamond && logs[i].topics[0] == IStrategyManager.StrategyDeployFailed.selector) {
                bytes memory reason = abi.decode(logs[i].data, (bytes));
                assertEq(bytes4(reason), IUniswapV3Adapter.UniswapV3AdapterDeployOffTwap.selector, "off-TWAP refusal");
                refused = true;
            }
        }
        assertTrue(refused, "deploy refused");
        pool.setSpotTick(TWAP_TICK);
        assertEq(vault.totalAssets(), nav, "NAV unmoved");
        assertEq(token0.balanceOf(address(adapter)), 500e18, "token0 still idle, still counted");
        assertEq(token1.balanceOf(address(adapter)), token1Amount, "token1 still idle");
        assertEq(adapter.tokenId(), 0, "no position");
    }

    /// @dev Moves spot to `spotTick`, funds token1 matching the idle token0 at spot (so the mint's own floors
    ///      pass) and rebalances. Asserts the deploy went through and stepped NAV by no more than `slippageBps`
    ///      (1%) of the token0 it consumed.
    function _assertDeployNavStepBoundedAtSpot(int24 spotTick) internal returns (int256 step) {
        npm.setPayAtSpot(true);
        token1.mint(address(adapter), _token1At(500e18, spotTick));
        pool.setSpotTick(spotTick);
        uint256 nav = vault.totalAssets();
        uint256 idle0 = token0.balanceOf(address(adapter));
        mgr.rebalance();
        assertGt(adapter.tokenId(), 0, "deployed");
        uint256 consumed = idle0 - token0.balanceOf(address(adapter));
        step = int256(vault.totalAssets()) - int256(nav);
        assertLe(_abs(step), (consumed * 100) / 10_000 + 2, "NAV step within slippageBps of the deploy");
    }

    function _abs(int256 x) internal pure returns (uint256) {
        return uint256(x < 0 ? -x : x);
    }

    /// @dev The keeper funds the token1 leg for the idle allocation and the manager deploys it.
    function _fundAndDeploy() internal {
        token1.mint(address(adapter), _token1For(500e18));
        vm.prank(diamond);
        adapter.deploy();
        assertLt(token0.balanceOf(address(adapter)), 1e18, "token0 deployed");
    }

    function _liquidity() internal view returns (uint128 liquidity) {
        (,,, liquidity,,) = npm.pos(adapter.tokenId());
    }

    /// @notice #221 PoC (b) shape on UniswapV3: the target drops to 10% while the allocation is still idle; the
    ///         recall is paid from idle token0.
    function test_UndeployedIdle_RecallSucceeds() public {
        _setTarget(address(adapter), 1_000);
        _rebalanceToTarget(address(adapter), 1_000);
        assertEq(vault.idleAssets(), 900e18, "400 recalled from idle token0");
    }

    /// @notice #271: the keeper's token1 is not vault NAV, before or after the deploy that pairs it, so at spot ==
    ///         TWAP funding and deploying never step the share price. Away from the TWAP a deploy steps NAV by the
    ///         gap on the token0 it consumes, refused beyond `slippageBps` (the `test_Deploy_*Twap*` cases).
    function test_KeeperToken1_NeverMovesNav() public {
        uint256 nav = vault.totalAssets();
        token1.mint(address(adapter), _token1For(500e18));
        assertEq(vault.totalAssets(), nav, "keeper token1 is not NAV");
        vm.prank(diamond);
        adapter.deploy();
        assertApproxEqAbs(vault.totalAssets(), nav, NAV_SLACK, "NAV flat across deploy");
    }

    /// @notice #271 review: a mint consumes token0 at spot while NAV counts the new token0 leg at the TWAP, so a
    ///         deploy with spot above the TWAP would inflate NAV by the gap. An attacker moving spot about 2x up to
    ///         match a keeper's over-funded token1 would turn the keeper's token1 into NAV (+20.7% here) inside
    ///         the permissionless `rebalance()`. The deploy is refused instead, and NAV does not move.
    function test_Deploy_SpotFarAboveTwap_Refused_NavFlat() public {
        _assertDeployRefusedAtSpot(TWAP_TICK + 6931, 2 * _token1For(500e18));
    }

    /// @notice #271 review, the mirror case: spot about 2x below the TWAP with the keeper's token1 half-funded
    ///         would deflate NAV (-14.6% here). The deploy is refused, and NAV does not move.
    function test_Deploy_SpotFarBelowTwap_Refused_NavFlat() public {
        _assertDeployRefusedAtSpot(TWAP_TICK - 6931, _token1For(500e18) / 2);
    }

    /// @notice #271 review: just past the bound (spot 250 ticks from the TWAP, a ~1.26% step on the deployed
    ///         token0 against a 1% `slippageBps`), a deploy funded at spot passes the mint's own floors and is still
    ///         refused.
    function test_Deploy_JustBeyondSlippageOfTwap_Refused() public {
        _assertDeployRefusedAtSpot(TWAP_TICK + 250, _token1At(500e18, TWAP_TICK + 250));
    }

    /// @notice #271 review: within the bound (spot 100 ticks above or below the TWAP) the deploy goes through,
    ///         and NAV steps by the spot/TWAP gap on the deployed token0 (about 0.5% here), never more than
    ///         `slippageBps` of it.
    function test_Deploy_WithinSlippageOfTwap_NavStepBounded() public {
        uint256 snap = vm.snapshotState();
        assertGt(_assertDeployNavStepBoundedAtSpot(TWAP_TICK + 100), 0, "spot above the TWAP steps NAV up");
        vm.revertToState(snap);
        assertLt(_assertDeployNavStepBoundedAtSpot(TWAP_TICK - 100), 0, "spot below the TWAP steps NAV down");
    }

    /// @notice #271 with #281's value-loss check: a lower target on a deployed position recalls only the idle
    ///         token0 (rounding dust here) and leaves the position whole, whether spot sits above, below or at the
    ///         TWAP. The recall loses no value, so rebalance completes as a partial recall and sends no token1.
    function test_DeployedPosition_RecallIsPartial_AtAnySpot() public {
        _fundAndDeploy();
        npm.setPayAtSpot(true);
        token0.mint(address(npm), 1_000e18); // the mock pays spot amounts from its own balance
        token1.mint(address(npm), 1_000e18);
        _setTarget(address(adapter), 4_000);
        uint128 liquidity = _liquidity();

        int24[3] memory spots = [TWAP_TICK + 2_000, TWAP_TICK - 2_000, TWAP_TICK];
        uint256 snap = vm.snapshotState();
        for (uint256 i; i < 3; ++i) {
            vm.revertToState(snap);
            pool.setSpotTick(spots[i]);
            uint256 nav = vault.totalAssets();
            uint256 requested = adapter.totalAssetsManaged() - (nav * 4_000) / 10_000;
            uint256 dust0 = token0.balanceOf(address(adapter));

            vm.expectEmit(true, false, false, true, diamond);
            emit IStrategyManager.StrategyPartiallyRecalled(address(adapter), requested, dust0);
            mgr.rebalance();
            assertEq(vault.totalAssets(), nav, "partial recall conserves NAV");
            assertEq(_liquidity(), liquidity, "position untouched");
            assertEq(token1.balanceOf(vaultAddr), 0, "no token1 sent to the vault");
        }
    }

    /// @notice #271: token1 is not NAV, so an adapter that holds only token1 counts as empty and can be added
    ///         without stepping the vault's NAV.
    function test_AddStrategy_AcceptsAdapterHoldingOnlyToken1() public {
        MockUniV3Adapter fresh = _newAdapter();
        token1.mint(address(fresh), 10e18);
        uint256 nav = vault.totalAssets();
        _addStrategy(address(fresh), 1_000);
        assertEq(vault.totalAssets(), nav, "NAV unchanged by the add");
    }

    /// @notice #271 exit path: rebalance cannot unwind a swap-free LP, so at target 0 it recalls the idle token0
    ///         only and `removeStrategy` refuses the still-counted token0 leg. The admin's `emergencyWithdraw` exits
    ///         the position: the vault receives the token0 leg, which NAV already counted, so NAV is conserved, and
    ///         the token1 leg, which was never NAV (the vault has no sweep for it). The emptied strategy can then be
    ///         removed.
    function test_TargetZero_ExitViaAdminEmergencyWithdraw_ConservesNav() public {
        _fundAndDeploy();
        token1.mint(address(adapter), 7e18); // stray idle token1, also uncounted

        _setTarget(address(adapter), 0);
        uint256 nav = vault.totalAssets();
        mgr.rebalance();
        assertEq(vault.totalAssets(), nav, "partial recall conserves NAV");
        uint256 leg0 = adapter.totalAssetsManaged();
        assertGt(leg0, 0, "the position's token0 leg is still counted");

        vm.expectRevert(
            abi.encodeWithSelector(
                IStrategyManager.StrategyManagerStrategyStillAllocated.selector, address(adapter), leg0
            )
        );
        vm.prank(admin);
        mgr.removeStrategy(address(adapter));

        vm.prank(admin);
        adapter.emergencyWithdraw();
        assertApproxEqAbs(vault.totalAssets(), nav, NAV_SLACK, "emergency exit conserves NAV");
        assertGt(token1.balanceOf(vaultAddr), 7e18, "token1 leg and stray token1 land in the vault, outside NAV");
        assertEq(adapter.totalAssetsManaged(), 0, "strategy emptied");

        vm.prank(admin);
        mgr.removeStrategy(address(adapter));
        assertEq(mgr.getStrategies().length, 0, "strategy removed");
    }
}
