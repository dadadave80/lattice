// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StrategyManagerTestBase} from "@lattice-test/base/StrategyManagerTestBase.sol";
import {VaultCoreTestBase} from "@lattice-test/base/VaultCoreTestBase.sol";
import {IMintableToken} from "@lattice-test/helpers/IMintableToken.sol";
import {StrategyManager} from "@lattice/defi/StrategyManager.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {IStrategyManager} from "@lattice/interfaces/defi/IStrategyManager.sol";
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
        asset.mint(address(pool), 7_777_777);
        asset.mint(address(adapter), 33_333_333); // undeployed idle
        _setTarget(address(adapter), 2_000);
        _rebalanceToTargetSpendingIdle(address(adapter), 2_000);
        assertEq(asset.balanceOf(address(adapter)), 0, "no idle left behind");
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

/// @notice UniswapV3 frees token0 and token1 together; the recall sends token0 and keeps token1 (still in NAV)
///         in the adapter, so rebalance completes at a non-integer TWAP price.
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

        adapter = new MockUniV3Adapter();
        adapter.initialize(admin, address(npm), address(pool), vaultAddr, treasury, 1800, 100);
        vm.prank(admin);
        adapter.setOperator(diamond);
        _addStrategy(address(adapter), 5_000);

        _deposit(address(token0), 1_000e18);
        // The swap-free adapter cannot deploy token0 alone: the deploy fails, is reported, and leaves the
        // allocation idle (and counted).
        mgr.rebalance();
        assertEq(token0.balanceOf(address(adapter)), 500e18, "allocation idle until the keeper funds token1");
    }

    /// @dev token1 matching `amount0` at the TWAP price, plus 0.5% so token0 is the binding side.
    function _token1For(uint256 amount0) internal pure returns (uint256) {
        uint160 sqrtP = UniswapV3FullRangeMath.getSqrtRatioAtTick(TWAP_TICK);
        uint256 a1 = Math.mulDiv(Math.mulDiv(amount0, sqrtP, 1 << 96), sqrtP, 1 << 96);
        return a1 + a1 / 200;
    }

    /// @notice #221 PoC (b) shape on UniswapV3: the target drops to 10% while the allocation is still idle; the
    ///         recall is paid from idle token0.
    function test_UndeployedIdle_RecallSucceeds() public {
        _setTarget(address(adapter), 1_000);
        _rebalanceToTarget(address(adapter), 1_000);
        assertEq(vault.idleAssets(), 900e18, "400 recalled from idle token0");
    }

    /// @notice #221: with the position deployed at a non-integer TWAP price, a recall frees token0 from the
    ///         position, keeps the freed token1 in the adapter, and conserves the vault's NAV.
    function test_DeployedPosition_NonIntegerTwap_RecallSucceeds() public {
        token1.mint(address(adapter), _token1For(500e18)); // keeper funds the token1 leg
        vm.prank(diamond);
        adapter.deploy();
        assertLt(token0.balanceOf(address(adapter)), 1e18, "token0 deployed");

        // 40% of the ~1502.5 NAV leaves a ~401 recall, inside the position's ~500 token0 leg.
        _setTarget(address(adapter), 4_000);
        uint256 idleBefore = vault.idleAssets();
        _rebalanceToTarget(address(adapter), 4_000);
        assertGt(vault.idleAssets(), idleBefore, "token0 recalled");
        assertEq(token1.balanceOf(vaultAddr), 0, "no token1 sent to the vault");
        assertGt(token1.balanceOf(address(adapter)), 0, "freed token1 held in the adapter");
    }

    /// @notice #221: the position pays out at spot while NAV is TWAP-valued. A full-range position's TWAP-valued
    ///         amounts are smallest at spot == TWAP, so a recall with spot pushed either way frees at least the
    ///         TWAP value it removes: rebalance completes (partial or exact) and NAV does not drop.
    function test_DeployedPosition_SpotAwayFromTwap_RecallNeverLosesValue() public {
        token1.mint(address(adapter), _token1For(500e18));
        vm.prank(diamond);
        adapter.deploy();
        npm.setPayAtSpot(true);
        token0.mint(address(npm), 1_000e18); // the mock pays spot amounts from its own balance
        token1.mint(address(npm), 1_000e18);
        _setTarget(address(adapter), 4_000);

        int24[2] memory spots = [TWAP_TICK + 2_000, TWAP_TICK - 2_000];
        uint256 snap = vm.snapshotState();
        for (uint256 i; i < 2; ++i) {
            vm.revertToState(snap);
            pool.setSpotTick(spots[i]);
            uint256 navBefore = vault.totalAssets();
            uint256 idleBefore = vault.idleAssets();
            mgr.rebalance();
            assertGe(vault.totalAssets() + NAV_SLACK, navBefore, "recall at spot != TWAP loses no value");
            assertGt(vault.idleAssets(), idleBefore, "token0 recalled");
        }
    }

    /// @notice #221 exit path: rebalance alone recalls only the token0 leg of a swap-free LP. At target 0 the
    ///         position is fully removed, the token1 stays idle in the adapter (still NAV), and every later
    ///         rebalance is a zero partial recall, so `removeStrategy` refuses. The admin `emergencyWithdraw`
    ///         realizes the token1 leg: it lands in the vault, which counts only token0, so NAV drops by its TWAP
    ///         value, and the emptied strategy can then be removed.
    function test_TargetZero_ExitNeedsAdminEmergencyWithdraw_ThenRemove() public {
        token1.mint(address(adapter), _token1For(500e18));
        vm.prank(diamond);
        adapter.deploy();

        _setTarget(address(adapter), 0);
        uint256 nav = vault.totalAssets();
        mgr.rebalance();
        assertApproxEqAbs(vault.totalAssets(), nav, NAV_SLACK, "full recall conserves NAV");
        (,,, uint128 liquidity,,) = npm.pos(adapter.tokenId());
        assertEq(liquidity, 0, "position fully removed");
        assertEq(token0.balanceOf(address(adapter)), 0, "every token0 recalled");
        uint256 idle1 = token1.balanceOf(address(adapter));
        assertGt(idle1, 0, "token1 leg held in the adapter");
        uint256 stranded = adapter.totalAssetsManaged();
        assertGt(stranded, 0, "token1 still counted");

        // Nothing token0 is left to recall: the next rebalance completes as a zero partial recall.
        vm.expectEmit(true, false, false, true, diamond);
        emit IStrategyManager.StrategyPartiallyRecalled(address(adapter), stranded, 0);
        mgr.rebalance();
        assertEq(adapter.totalAssetsManaged(), stranded, "token1 cannot leave through rebalance");

        vm.expectRevert(
            abi.encodeWithSelector(
                IStrategyManager.StrategyManagerStrategyStillAllocated.selector, address(adapter), stranded
            )
        );
        vm.prank(admin);
        mgr.removeStrategy(address(adapter));

        // Admin realizes the token1 leg: it moves to the vault, outside NAV.
        nav = vault.totalAssets();
        vm.prank(admin);
        adapter.emergencyWithdraw();
        assertEq(token1.balanceOf(vaultAddr), idle1, "token1 sent to the vault");
        assertEq(adapter.totalAssetsManaged(), 0, "strategy emptied");
        assertEq(vault.totalAssets(), nav - stranded, "NAV drops by the token1 TWAP value");

        vm.prank(admin);
        mgr.removeStrategy(address(adapter));
        assertEq(mgr.getStrategies().length, 0, "strategy removed");
    }
}
