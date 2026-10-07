// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployStrategyManager} from "@lattice-script/base/defi/DeployStrategyManager.s.sol";
import {DeployVaultCore} from "@lattice-script/base/defi/DeployVaultCore.s.sol";
import {ERC4626TestBase} from "@lattice-test/base/ERC4626TestBase.sol";
import {GovernedVaultTestBase} from "@lattice-test/base/GovernedVaultTestBase.sol";
import {StrategyManagerTestBase} from "@lattice-test/base/StrategyManagerTestBase.sol";
import {VaultCoreTestBase} from "@lattice-test/base/VaultCoreTestBase.sol";
import {IMintableToken} from "@lattice-test/helpers/IMintableToken.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {StrategyManager} from "@lattice/defi/StrategyManager.sol";
import {IStrategyManager} from "@lattice/interfaces/defi/IStrategyManager.sol";
import {IVaultCore} from "@lattice/interfaces/defi/IVaultCore.sol";
import {IStrategy} from "@lattice/interfaces/external/yearn/IStrategy.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                 FIXTURES
//////////////////////////////////////////////////////////////////////////*//

/// @notice Strategy that holds the vault's allocated tokens and reports its live balance.
/// @dev `brick()` makes `totalAssetsManaged()` revert, simulating a strategy whose NAV read is broken;
///      `unbrick()` models a transient failure recovering. `report()` overrides the reported balance.
contract NavStrategy is IStrategy {
    IMintableToken public immutable token;
    bool public bricked;
    bool public overridden;
    uint256 public reported;

    constructor(IMintableToken token_) {
        token = token_;
    }

    function brick() external {
        bricked = true;
    }

    function unbrick() external {
        bricked = false;
    }

    function report(uint256 value) external {
        overridden = true;
        reported = value;
    }

    function asset() external view override returns (address) {
        return address(token);
    }

    function totalAssetsManaged() external view override returns (uint256) {
        require(!bricked, "strategy bricked");
        return overridden ? reported : token.balanceOf(address(this));
    }

    function withdraw(uint256 amount, address to) external override returns (uint256) {
        token.transfer(to, amount);
        return amount;
    }
}

/// @notice Plain mintable ERC-20 for the governed-vault suite.
contract NavAsset {
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                 VAULTCORE + STRATEGYMANAGER RECIPE DIAMONDS
//////////////////////////////////////////////////////////////////////////*//

/// @title VaultFullNavPricingTest
/// @notice Regression for #214 on the production {DeployVaultCore} + {DeployStrategyManager} diamonds: once a
///         strategy holds allocated funds, ERC-4626 share math must price on the vault's full NAV
///         (`totalAssets()` = idle + strategy-reported), while exits stay capped at idle liquidity.
contract VaultFullNavPricingTest is VaultCoreTestBase, StrategyManagerTestBase {
    NavStrategy internal strategy;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    uint256 internal constant DEPOSIT = 1_000e18;
    uint256 internal constant ALLOCATED = 500e18; // 50% target
    uint256 internal constant IDLE = DEPOSIT - ALLOCATED;

    function setUp() public override {
        super.setUp(); // underlying ERC-20 diamond + VaultCore diamond, admin = 0xAD

        diamond = _deployStrategyManager(admin);
        mgr = StrategyManager(diamond);
        strategy = new NavStrategy(underlying);

        vm.startPrank(admin);
        vault.setStrategyManager(diamond);
        mgr.setVault(vaultAddr);
        mgr.addStrategy(address(strategy), 5_000);
        vm.stopPrank();

        _deposit(alice, DEPOSIT);
        mgr.rebalance(); // pushes 50% of NAV into the strategy
    }

    function _deposit(address who, uint256 assets) internal returns (uint256 shares) {
        underlying.mint(who, assets);
        vm.startPrank(who);
        underlying.approve(vaultAddr, assets);
        shares = vault.deposit(assets, who);
        vm.stopPrank();
    }

    function test_Setup_StrategyHoldsAllocatedFunds() public view {
        assertEq(underlying.balanceOf(address(strategy)), ALLOCATED, "strategy holds 50%");
        assertEq(vault.idleAssets(), IDLE, "vault keeps 50% idle");
        assertEq(vault.totalAssets(), DEPOSIT, "NAV = idle + allocated");
        assertEq(vault.totalSupply(), DEPOSIT, "1:1 shares");
    }

    /// @notice The converters and previews must use the full NAV, not the idle balance.
    function test_ConvertersPriceOnFullNav() public view {
        assertEq(vault.convertToAssets(DEPOSIT), DEPOSIT, "convertToAssets");
        assertEq(vault.convertToShares(100e18), 100e18, "convertToShares");
        assertEq(vault.previewDeposit(100e18), 100e18, "previewDeposit");
        assertEq(vault.previewMint(100e18), 100e18, "previewMint");
        assertEq(vault.previewWithdraw(IDLE), IDLE, "previewWithdraw");
        assertEq(vault.previewRedeem(IDLE), IDLE, "previewRedeem");
    }

    /// @notice A deposit made while funds are deployed is priced fairly: no dilution of existing holders.
    function test_DepositWhileAllocated_DoesNotDilute() public {
        uint256 shares = _deposit(bob, 100e18);
        assertEq(shares, 100e18, "bob gets NAV-priced shares");
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), DEPOSIT, "alice keeps her full NAV");
        assertEq(vault.convertToAssets(vault.balanceOf(bob)), 100e18, "bob's claim equals his deposit");
    }

    /// @notice Yield earned inside a strategy accrues to share holders through the NAV.
    function test_StrategyYieldAccruesToHolders() public {
        underlying.mint(address(strategy), 100e18);
        uint256 nav = DEPOSIT + 100e18;
        assertEq(vault.totalAssets(), nav, "NAV includes strategy yield");
        assertEq(vault.convertToAssets(DEPOSIT), DEPOSIT * (nav + 1) / (DEPOSIT + 1), "shares priced on NAV");
    }

    /// @notice The NAV self-staticcall reaches the diamond's own `totalAssets()` (VaultCore's selector).
    function test_ConverterReadsDiamondTotalAssets() public {
        vm.expectCall(vaultAddr, abi.encodeCall(IERC4626.totalAssets, ()));
        vault.convertToAssets(1e18);
    }

    /// @notice Exits are capped at idle liquidity: the allocated half cannot be paid out.
    function test_MaxWithdrawAndMaxRedeem_CappedAtIdle() public view {
        assertEq(vault.maxWithdraw(alice), IDLE, "maxWithdraw = idle");
        assertEq(vault.maxRedeem(alice), IDLE, "maxRedeem = shares worth idle");
    }

    function test_RedeemAboveIdle_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC4626.ERC4626ExceededMaxRedeem.selector, alice, DEPOSIT, IDLE));
        vault.redeem(DEPOSIT, alice, alice);
    }

    function test_WithdrawAboveIdle_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC4626.ERC4626ExceededMaxWithdraw.selector, alice, IDLE + 1, IDLE));
        vault.withdraw(IDLE + 1, alice, alice);
    }

    /// @notice Redeeming `maxRedeem` pays exactly the NAV value of those shares, and the rest keep their value.
    function test_RedeemMaxRedeem_PaysExactNav() public {
        uint256 maxShares = vault.maxRedeem(alice);
        vm.prank(alice);
        uint256 assets = vault.redeem(maxShares, alice, alice);

        assertEq(assets, IDLE, "paid the NAV value of the redeemed shares");
        assertEq(underlying.balanceOf(alice), IDLE, "alice received the assets");
        assertEq(vault.balanceOf(alice), DEPOSIT - IDLE, "half the shares remain");
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), ALLOCATED, "remaining shares keep their NAV");
    }

    /// @notice A reverting strategy NAV read fails closed: no entry, no exit, `max*` report 0.
    function test_RevertingStrategy_FailsClosed() public {
        strategy.brick();

        vm.expectRevert(abi.encodeWithSelector(IVaultCore.VaultCoreStrategyNavUnavailable.selector, diamond));
        vault.totalAssets();

        assertEq(vault.maxDeposit(bob), 0, "maxDeposit");
        assertEq(vault.maxMint(bob), 0, "maxMint");
        assertEq(vault.maxWithdraw(alice), 0, "maxWithdraw");
        assertEq(vault.maxRedeem(alice), 0, "maxRedeem");

        vm.expectRevert(abi.encodeWithSelector(IVaultCore.VaultCoreStrategyNavUnavailable.selector, diamond));
        vault.previewRedeem(1e18);

        underlying.mint(bob, 1e18);
        vm.startPrank(bob);
        underlying.approve(vaultAddr, 1e18);
        vm.expectRevert(abi.encodeWithSelector(IERC4626.ERC4626ExceededMaxDeposit.selector, bob, 1e18, 0));
        vault.deposit(1e18, bob);
        vm.expectRevert(abi.encodeWithSelector(IERC4626.ERC4626ExceededMaxMint.selector, bob, 1e18, 0));
        vault.mint(1e18, bob);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC4626.ERC4626ExceededMaxRedeem.selector, alice, 1, 0));
        vault.redeem(1, alice, alice);
    }

    /// @notice The admin can force-remove a strategy whose NAV read reverts, restoring the vault.
    function test_RevertingStrategy_ForceRemovedRestoresVault() public {
        strategy.brick();

        vm.expectEmit(true, false, false, false, diamond);
        emit IStrategyManager.StrategyForceRemoved(address(strategy));
        vm.expectEmit(true, false, false, false, diamond);
        emit IStrategyManager.StrategyRemoved(address(strategy));
        vm.prank(admin);
        mgr.removeStrategy(address(strategy));

        assertEq(mgr.getStrategies().length, 0, "strategy removed");
        assertEq(mgr.totalTargetBps(), 0, "target released");
        assertEq(vault.totalAssets(), IDLE, "stranded funds leave the NAV");
        assertEq(vault.maxWithdraw(alice), IDLE, "exits reopen");
        assertGt(vault.maxDeposit(bob), 0, "entries reopen");
    }

    /// @notice A force-removed strategy cannot be re-added while it still holds the stranded funds: re-adding
    ///         would step the NAV back up and hand the stranded value to whoever deposited at the idle-only
    ///         NAV after the removal (here bob gets ~2x shares per asset).
    function test_ForceRemovedStrategy_ReaddWhileHoldingFunds_Reverts() public {
        strategy.brick();
        vm.prank(admin);
        mgr.removeStrategy(address(strategy));
        assertEq(vault.totalAssets(), IDLE, "stranded funds left the NAV");

        // The window this test documents: deposits reopen at the idle-only NAV.
        uint256 bobShares = _deposit(bob, DEPOSIT);
        assertApproxEqAbs(bobShares, 2 * DEPOSIT, 2, "bob priced on idle only");

        strategy.unbrick();
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStrategyManager.StrategyManagerStrategyNotEmpty.selector, address(strategy), ALLOCATED
            )
        );
        mgr.addStrategy(address(strategy), 5_000);
        assertEq(vault.totalAssets(), IDLE + DEPOSIT, "NAV did not step up");
    }

    /// @notice A strategy whose balance read reverts cannot be added: it would freeze the vault on the spot.
    function test_AddStrategy_RevertingRead_Reverts() public {
        NavStrategy fresh = new NavStrategy(underlying);
        fresh.brick();
        vm.prank(admin);
        vm.expectRevert(bytes("strategy bricked"));
        mgr.addStrategy(address(fresh), 1_000);
    }

    /// @notice A strategy reporting an overflowing balance freezes the vault (the sum panics), but its
    ///         well-formed read is not a failed read, so `removeStrategy` cannot force-remove it. The last-resort
    ///         recovery is the vault admin pointing `setStrategyManager` at a fresh manager; the stranded funds
    ///         then leave the NAV.
    function test_OverflowingStrategy_RecoveredBySetStrategyManager() public {
        strategy.report(type(uint256).max);
        assertEq(vault.maxDeposit(bob), 0, "frozen: maxDeposit");
        assertEq(vault.maxRedeem(alice), 0, "frozen: maxRedeem");

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStrategyManager.StrategyManagerStrategyStillAllocated.selector, address(strategy), type(uint256).max
            )
        );
        mgr.removeStrategy(address(strategy));

        address freshMgr = _deployStrategyManager(admin);
        vm.prank(admin);
        vault.setStrategyManager(freshMgr);

        assertEq(vault.totalAssets(), IDLE, "NAV = idle; stranded funds left it");
        assertEq(vault.maxRedeem(alice), IDLE * (DEPOSIT + 1) / (IDLE + 1), "exits reopen");
        assertGt(vault.maxDeposit(bob), 0, "entries reopen");
    }

    /// @notice Force removal is admin-gated like a normal removal.
    function test_RevertingStrategy_ForceRemove_NonAdminReverts() public {
        strategy.brick();
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), bob, bytes32(0)
            )
        );
        mgr.removeStrategy(address(strategy));
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                    RECIPE-DIAMOND FUZZ (IDLE CAP, NO DILUTION)
//////////////////////////////////////////////////////////////////////////*//

/// @notice Fuzzes the #214 properties on a recipe VaultCore + StrategyManager diamond whose strategy holds a
///         random share of the funds and a random yield or loss: a deposit never dilutes existing holders by
///         more than 1 wei, `max*` exits never promise more than idle liquidity and never revert, and the
///         previews match the executed exits.
abstract contract VaultFullNavFuzzBase is VaultCoreTestBase, StrategyManagerTestBase {
    NavStrategy internal strategy;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function _offset() internal pure virtual returns (uint8);

    function setUp() public override {
        super.setUp();
        vaultDeployer = new DeployVaultCore();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            vaultDeployer.buildCuts(underlyingAddr, "Vault Share", "vSHARE", admin, _offset());
        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        vaultAddr = address(d);
        vault = IVaultCore(vaultAddr);

        diamond = _deployStrategyManager(admin);
        mgr = StrategyManager(diamond);
        strategy = new NavStrategy(underlying);

        vm.startPrank(admin);
        vault.setStrategyManager(diamond);
        mgr.setVault(vaultAddr);
        mgr.addStrategy(address(strategy), 5_000);
        vm.stopPrank();
    }

    function _deposit(address who, uint256 assets) internal returns (uint256 shares) {
        underlying.mint(who, assets);
        vm.startPrank(who);
        underlying.approve(vaultAddr, assets);
        shares = vault.deposit(assets, who);
        vm.stopPrank();
    }

    /// @dev `who`'s claim on the full NAV (`totalAssets()` = idle + strategy), computed independently of the
    ///      vault's converters so that a converter pricing on idle only cannot hide the dilution.
    function _navValue(address who) internal view returns (uint256) {
        return vault.balanceOf(who) * (vault.totalAssets() + 1) / (vault.totalSupply() + 10 ** _offset());
    }

    function testFuzz_MaxExitsCappedAtIdle_NoDilution(
        uint96 a,
        uint96 b,
        uint16 bps,
        uint96 yield_,
        uint96 loss,
        bool aliceExits,
        bool redeem
    ) public {
        vm.prank(admin);
        mgr.updateStrategyTarget(address(strategy), uint16(bound(bps, 0, 10_000)));
        _deposit(alice, bound(a, 1, 1e30));
        mgr.rebalance();

        underlying.mint(address(strategy), bound(yield_, 0, 1e30));
        uint256 l = bound(loss, 0, underlying.balanceOf(address(strategy)));
        if (l > 0) {
            vm.prank(address(strategy));
            underlying.transfer(address(0xdead), l);
        }

        uint256 aliceBefore = _navValue(alice);
        _deposit(bob, bound(b, 1, 1e30));
        assertGe(_navValue(alice) + 1, aliceBefore, "deposit diluted alice");

        address who = aliceExits ? alice : bob;
        uint256 idle = vault.idleAssets();
        uint256 maxShares = vault.maxRedeem(who);
        uint256 maxAssets = vault.maxWithdraw(who);
        assertLe(maxAssets, idle, "maxWithdraw > idle");
        assertLe(vault.previewRedeem(maxShares), idle, "previewRedeem(maxRedeem) > idle");

        vm.startPrank(who);
        if (redeem) {
            uint256 expected = vault.previewRedeem(maxShares);
            assertEq(vault.redeem(maxShares, who, who), expected, "redeem != previewRedeem");
        } else {
            uint256 expected = vault.previewWithdraw(maxAssets);
            assertEq(vault.withdraw(maxAssets, who, who), expected, "withdraw != previewWithdraw");
        }
        vm.stopPrank();
    }
}

contract VaultFullNavFuzzTest is VaultFullNavFuzzBase {
    function _offset() internal pure override returns (uint8) {
        return 0;
    }
}

contract VaultFullNavOffsetFuzzTest is VaultFullNavFuzzBase {
    function _offset() internal pure override returns (uint8) {
        return 6;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                       GOVERNED VAULT RECIPE DIAMOND
//////////////////////////////////////////////////////////////////////////*//

/// @title GovernedVaultFullNavPricingTest
/// @notice The same #214 regression on the production {DeployGovernedVault} diamond, whose deposit/mint/
///         withdraw/redeem are the {GovernedVault} vote-checkpoint wrappers over {ERC4626Lib}.
contract GovernedVaultFullNavPricingTest is GovernedVaultTestBase {
    NavAsset internal asset;
    NavStrategy internal strategy;
    address internal vaultAddr;
    IVaultCore internal vault;
    StrategyManager internal mgr;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    uint256 internal constant DEPOSIT = 1_000e18;
    uint256 internal constant IDLE = 500e18;

    function setUp() public {
        vm.warp(1_000_000);
        asset = new NavAsset();

        GovernedVaultParams memory p;
        p.name = "Governed Vault Share";
        p.symbol = "gVLT";
        p.minDelay = 100;
        p.votingDelay = 1;
        p.votingPeriod = 50;
        p.quorumNumerator = 4;
        vaultAddr = _deployGovernedVault(address(asset), p);
        vault = IVaultCore(vaultAddr);

        DeployStrategyManager mgrDeployer = new DeployStrategyManager();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = mgrDeployer.buildCuts(address(this));
        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        mgr = StrategyManager(address(d));

        strategy = new NavStrategy(IMintableToken(address(asset)));
        mgr.setVault(vaultAddr);
        mgr.addStrategy(address(strategy), 5_000);
        // The diamond is its own DEFAULT_ADMIN_ROLE holder (a passed proposal makes this same call).
        vm.prank(vaultAddr);
        vault.setStrategyManager(address(mgr));

        _deposit(alice, DEPOSIT);
        mgr.rebalance();
    }

    function _deposit(address who, uint256 assets) internal returns (uint256 shares) {
        asset.mint(who, assets);
        vm.startPrank(who);
        asset.approve(vaultAddr, assets);
        shares = vault.deposit(assets, who);
        vm.stopPrank();
    }

    function test_Governed_DepositWhileAllocated_DoesNotDilute() public {
        assertEq(vault.idleAssets(), IDLE, "half deployed");
        assertEq(vault.totalAssets(), DEPOSIT, "NAV = idle + allocated");
        assertEq(vault.previewDeposit(100e18), 100e18, "previewDeposit on NAV");

        uint256 shares = _deposit(bob, 100e18);
        assertEq(shares, 100e18, "bob gets NAV-priced shares");
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), DEPOSIT, "alice keeps her full NAV");
    }

    function test_Governed_ExitsCappedAtIdle() public {
        assertEq(vault.maxWithdraw(alice), IDLE, "maxWithdraw = idle");
        assertEq(vault.maxRedeem(alice), IDLE, "maxRedeem = shares worth idle");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC4626.ERC4626ExceededMaxRedeem.selector, alice, DEPOSIT, IDLE));
        vault.redeem(DEPOSIT, alice, alice);

        vm.prank(alice);
        uint256 assets = vault.redeem(IDLE, alice, alice);
        assertEq(assets, IDLE, "paid the NAV value of the redeemed shares");
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), DEPOSIT - IDLE, "remaining shares keep their NAV");
    }

    function test_Governed_RevertingStrategy_FailsClosed() public {
        strategy.brick();
        assertEq(vault.maxDeposit(bob), 0, "maxDeposit");
        assertEq(vault.maxRedeem(alice), 0, "maxRedeem");

        asset.mint(bob, 1e18);
        vm.startPrank(bob);
        asset.approve(vaultAddr, 1e18);
        vm.expectRevert(abi.encodeWithSelector(IERC4626.ERC4626ExceededMaxDeposit.selector, bob, 1e18, 0));
        vault.deposit(1e18, bob);
        vm.stopPrank();
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                    ERC-4626-ONLY DIAMOND (NO VAULTCORE)
//////////////////////////////////////////////////////////////////////////*//

/// @title ERC4626NavSelfCallTest
/// @notice On a plain {DeployERC4626} diamond the NAV self-staticcall lands on the {ERC4626} facet's idle-only
///         `totalAssets()` — it must not recurse back into the converters.
contract ERC4626NavSelfCallTest is ERC4626TestBase {
    address internal alice = address(0xA11CE);

    function setUp() public override {
        super.setUp();
        underlying.mint(alice, 1_000e18);
        vm.startPrank(alice);
        underlying.approve(vaultAddr, 1_000e18);
        vault.deposit(1_000e18, alice);
        vm.stopPrank();
        underlying.mint(vaultAddr, 100e18); // donation
    }

    function test_SelfCall_ReachesIdleOnlyTotalAssets_NoRecursion() public {
        uint256 expected = uint256(1_000e18) * (1_100e18 + 1) / (1_000e18 + 1);
        assertEq(vault.totalAssets(), underlying.balanceOf(vaultAddr), "totalAssets stays idle-only");
        assertEq(vault.maxWithdraw(alice), expected, "all NAV is idle, so no cap applies");
        assertEq(vault.maxRedeem(alice), vault.balanceOf(alice), "redeem side uncapped too");

        // Exactly one self-call: the {ERC4626} facet's `totalAssets()` does not re-enter the converters.
        vm.expectCall(vaultAddr, abi.encodeCall(IERC4626.totalAssets, ()), 1);
        assertEq(vault.previewRedeem(1_000e18), expected, "priced on the idle NAV");
    }
}
