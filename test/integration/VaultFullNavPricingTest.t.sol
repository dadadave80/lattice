// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
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
import {IStrategyManagerRecovery} from "@lattice/interfaces/defi/IStrategyManagerRecovery.sol";
import {IVaultCore} from "@lattice/interfaces/defi/IVaultCore.sol";
import {IVaultCoreRecovery} from "@lattice/interfaces/defi/IVaultCoreRecovery.sol";
import {IStrategy} from "@lattice/interfaces/external/yearn/IStrategy.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {stdError} from "forge-std/StdError.sol";
import {Vm} from "forge-std/Vm.sol";

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

/// @notice A strategy manager built before the deposit latch: it has no `depositsLatched()` selector.
contract LegacyManager {
    function totalAllocated() external pure returns (uint256) {
        return 0;
    }

    function reentrancyGuardEntered() external pure returns (bool) {
        return false;
    }
}

/// @notice A broken manager: `depositsLatched()` reads false but `totalAllocated()` burns all the gas it is given.
contract GasBurnManager {
    function depositsLatched() external pure returns (bool) {
        return false;
    }

    function totalAllocated() external view returns (uint256 n) {
        while (gasleft() > 0) {
            ++n;
        }
    }

    function reentrancyGuardEntered() external pure returns (bool) {
        return false;
    }
}

/// @notice A broken manager: `depositsLatched()` answers 4 zero bytes, short of a full word; `totalAllocated()`
///         answers a clean 0.
contract ShortLatchReadManager {
    function depositsLatched() external pure returns (bool) {
        assembly ("memory-safe") {
            mstore(0x00, 0)
            return(0x00, 0x04)
        }
    }

    function totalAllocated() external pure returns (uint256) {
        return 0;
    }

    function reentrancyGuardEntered() external pure returns (bool) {
        return false;
    }
}

/// @notice A broken manager: `depositsLatched()` answers a clean false; `totalAllocated()` answers 4 zero bytes,
///         short of a full word.
contract ShortAllocatedReadManager {
    function depositsLatched() external pure returns (bool) {
        return false;
    }

    function totalAllocated() external pure returns (uint256) {
        assembly ("memory-safe") {
            mstore(0x00, 0)
            return(0x00, 0x04)
        }
    }

    function reentrancyGuardEntered() external pure returns (bool) {
        return false;
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

    /// @notice The admin can force-remove a strategy whose NAV read reverts, restoring the vault: exits reopen at
    ///         once, entries once the admin clears the deposit latch the removal set.
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
        assertEq(vault.maxDeposit(bob), 0, "entries latched");

        vm.prank(admin);
        mgr.clearDepositLatch();
        assertGt(vault.maxDeposit(bob), 0, "entries reopen once cleared");
    }

    /// @notice A force-removed strategy cannot be re-added while it still holds the stranded funds: re-adding
    ///         would step the NAV back up and hand the stranded value to whoever deposited at the idle-only
    ///         NAV after the removal (here bob gets ~2x shares per asset once the admin clears the latch).
    function test_ForceRemovedStrategy_ReaddWhileHoldingFunds_Reverts() public {
        strategy.brick();
        vm.prank(admin);
        mgr.removeStrategy(address(strategy));
        assertEq(vault.totalAssets(), IDLE, "stranded funds left the NAV");

        // The window this test documents: once the latch is cleared, deposits price on the idle-only NAV.
        vm.prank(admin);
        mgr.clearDepositLatch();
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
    ///         then leave the NAV. The old manager still reports allocations (its one-term sum is
    ///         `type(uint256).max`; only the vault's `idle + allocated` panics), so the swap latches deposits on
    ///         the vault (#305): exits reopen at once, entries once the vault admin clears the latch.
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
        assertFalse(mgr.depositsLatched(), "old manager never latched");
        assertEq(mgr.totalAllocated(), type(uint256).max, "old manager still reports allocations");

        address freshMgr = _deployStrategyManager(admin);
        vm.expectEmit(true, false, false, false, vaultAddr);
        emit IVaultCoreRecovery.ManagerSwapLatchSet(diamond);
        vm.prank(admin);
        vault.setStrategyManager(freshMgr);

        assertEq(vault.totalAssets(), IDLE, "NAV = idle; stranded funds left it");
        assertEq(vault.maxRedeem(alice), IDLE * (DEPOSIT + 1) / (IDLE + 1), "exits reopen");
        _assertEntriesLatched(vaultAddr);

        vm.prank(admin);
        IVaultCoreRecovery(vaultAddr).clearManagerSwapLatch();
        assertGt(vault.maxDeposit(bob), 0, "entries reopen once cleared");
    }

    /// @notice Two overflowing strategies make the old manager's own `totalAllocated()` sum panic. That failed read
    ///         cannot block the last-resort swap, and it latches (#305).
    function test_OverflowingStrategies_ManagerSumPanics_SwapLatches() public {
        NavStrategy second = new NavStrategy(underlying);
        vm.prank(admin);
        mgr.addStrategy(address(second), 1_000);
        strategy.report(type(uint256).max);
        second.report(1);
        vm.expectRevert(stdError.arithmeticError);
        mgr.totalAllocated();

        address freshMgr = _deployStrategyManager(admin);
        vm.expectEmit(true, false, false, false, vaultAddr);
        emit IVaultCoreRecovery.ManagerSwapLatchSet(diamond);
        vm.prank(admin);
        vault.setStrategyManager(freshMgr);

        assertEq(vault.strategyManager(), freshMgr, "swap went through");
        assertEq(vault.totalAssets(), IDLE, "NAV = idle; stranded funds left it");
        _assertEntriesLatched(vaultAddr);
    }

    /// @notice #270 regression: the donation-capture sandwich after a force removal. Once the bricked strategy
    ///         leaves the NAV, a depositor entering at the idle-only price would capture half of any funds the
    ///         strategy later returns (bob ~2x shares per asset, then a 500 return). The latch keeps entries
    ///         closed until the admin clears it, so the returned funds accrue to the holders who stayed.
    function test_ForceRemoval_DonationSandwich_DepositsLatched() public {
        strategy.brick();
        vm.prank(admin);
        mgr.removeStrategy(address(strategy));

        // Step 1 of the sandwich: enter at the idle-only NAV. Refused while latched.
        assertEq(vault.maxDeposit(bob), 0, "maxDeposit while latched");
        assertEq(vault.maxMint(bob), 0, "maxMint while latched");
        underlying.mint(bob, DEPOSIT);
        vm.startPrank(bob);
        underlying.approve(vaultAddr, DEPOSIT);
        vm.expectRevert(abi.encodeWithSelector(IVaultCore.VaultCoreDepositsLatched.selector, diamond));
        vault.deposit(DEPOSIT, bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultCore.VaultCoreDepositsLatched.selector, diamond));
        vault.mint(DEPOSIT, bob);
        vm.stopPrank();

        // Step 2: the stranded funds come back as a plain transfer.
        strategy.unbrick();
        vm.prank(address(strategy));
        underlying.transfer(vaultAddr, ALLOCATED);

        assertEq(vault.balanceOf(bob), 0, "bob holds no shares");
        assertEq(vault.totalAssets(), DEPOSIT, "the full NAV is back");
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), DEPOSIT, "alice keeps the returned funds");

        // The admin clears the latch once recovery is done; bob now enters at the full NAV.
        vm.prank(admin);
        mgr.clearDepositLatch();
        vm.prank(bob);
        assertEq(vault.deposit(DEPOSIT, bob), DEPOSIT, "bob priced on the full NAV");
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), DEPOSIT, "alice not diluted");
    }

    /// @notice While latched, exits stay open (capped at idle); only entries are closed.
    function test_DepositLatch_ExitsStayOpen() public {
        strategy.brick();
        vm.prank(admin);
        mgr.removeStrategy(address(strategy));

        assertEq(vault.maxWithdraw(alice), IDLE, "maxWithdraw = idle");
        assertEq(vault.maxRedeem(alice), IDLE * (DEPOSIT + 1) / (IDLE + 1), "maxRedeem capped at idle");
        vm.startPrank(alice);
        vault.withdraw(100e18, alice, alice);
        assertEq(underlying.balanceOf(alice), 100e18, "withdraw paid");
        uint256 out = vault.redeem(vault.maxRedeem(alice), alice, alice);
        vm.stopPrank();
        assertGt(out, 0, "redeem paid");
        assertLe(underlying.balanceOf(alice), IDLE, "exits never exceed idle");
    }

    /// @notice A force removal sets the latch and emits DepositLatchSet after StrategyForceRemoved.
    function test_DepositLatch_SetByForceRemoval_Events() public {
        assertFalse(mgr.depositsLatched(), "starts unlatched");
        strategy.brick();

        vm.expectEmit(true, false, false, false, diamond);
        emit IStrategyManager.StrategyForceRemoved(address(strategy));
        vm.expectEmit(true, false, false, false, diamond);
        emit IStrategyManagerRecovery.DepositLatchSet(address(strategy));
        vm.expectEmit(true, false, false, false, diamond);
        emit IStrategyManager.StrategyRemoved(address(strategy));
        vm.prank(admin);
        mgr.removeStrategy(address(strategy));

        assertTrue(mgr.depositsLatched(), "latched");
    }

    /// @notice A normal (empty-strategy) removal does not latch.
    function test_DepositLatch_NotSetByNormalRemoval() public {
        vm.prank(admin);
        mgr.updateStrategyTarget(address(strategy), 0);
        mgr.rebalance(); // recalls everything
        vm.prank(admin);
        mgr.removeStrategy(address(strategy));

        assertFalse(mgr.depositsLatched(), "not latched");
        assertEq(vault.maxDeposit(bob), type(uint256).max, "maxDeposit open");
        assertEq(_deposit(bob, 1e18), 1e18, "deposit open");
    }

    /// @notice Only DEFAULT_ADMIN_ROLE clears; the clear emits DepositLatchCleared and reopens entries.
    function test_DepositLatch_Clear_AuthAndEvent() public {
        strategy.brick();
        vm.prank(admin);
        mgr.removeStrategy(address(strategy));

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), bob, bytes32(0)
            )
        );
        mgr.clearDepositLatch();
        assertTrue(mgr.depositsLatched(), "still latched");

        vm.expectEmit(true, false, false, false, diamond);
        emit IStrategyManagerRecovery.DepositLatchCleared(admin);
        vm.prank(admin);
        mgr.clearDepositLatch();

        assertFalse(mgr.depositsLatched(), "cleared");
        assertEq(vault.maxDeposit(bob), type(uint256).max, "maxDeposit reopens");
        assertEq(vault.maxMint(bob), type(uint256).max, "maxMint reopens");
        assertGt(_deposit(bob, 1e18), 0, "deposit reopens");
    }

    /// @notice Clearing an unset latch reverts.
    function test_DepositLatch_ClearWhenNotSet_Reverts() public {
        vm.prank(admin);
        vm.expectRevert(IStrategyManagerRecovery.StrategyManagerDepositLatchNotSet.selector);
        mgr.clearDepositLatch();
    }

    /// @dev Points the vault at a fresh recipe-built manager as the vault admin and returns it.
    function _swapToFreshManager() internal returns (address freshMgr) {
        freshMgr = _deployStrategyManager(admin);
        vm.prank(admin);
        vault.setStrategyManager(freshMgr);
    }

    /// @dev Recalls everything from the strategy so the configured manager reports nothing allocated.
    function _drainStrategy() internal {
        vm.prank(admin);
        mgr.updateStrategyTarget(address(strategy), 0);
        mgr.rebalance();
        assertEq(mgr.totalAllocated(), 0, "drained");
    }

    /// @dev Asserts entries are latched closed with `holder` named in the revert, while exits stay open.
    function _assertEntriesLatched(address holder) internal {
        assertEq(vault.maxDeposit(bob), 0, "maxDeposit while latched");
        assertEq(vault.maxMint(bob), 0, "maxMint while latched");
        underlying.mint(bob, 1e18);
        vm.startPrank(bob);
        underlying.approve(vaultAddr, 1e18);
        vm.expectRevert(abi.encodeWithSelector(IVaultCore.VaultCoreDepositsLatched.selector, holder));
        vault.deposit(1e18, bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultCore.VaultCoreDepositsLatched.selector, holder));
        vault.mint(1e18, bob);
        vm.stopPrank();
        assertGt(vault.maxWithdraw(alice), 0, "exits stay open");
    }

    /// @notice #305 regression: swapping out a latched manager carries the latch over to the vault. Deposits stay
    ///         closed on the fresh manager until the vault admin clears it, so the force-removed strategy's funds,
    ///         returned after the swap, stay with the holders from the time of the removal.
    function test_DepositLatch_ManagerSwapCarriesLatch() public {
        strategy.brick();
        vm.prank(admin);
        mgr.removeStrategy(address(strategy));
        assertEq(vault.maxDeposit(bob), 0, "latched");

        address freshMgr = _swapToFreshManager();
        assertTrue(mgr.depositsLatched(), "old manager still latched");
        assertFalse(StrategyManager(freshMgr).depositsLatched(), "fresh manager starts unlatched");
        assertTrue(IVaultCoreRecovery(vaultAddr).managerSwapLatched(), "latch carried to the vault");
        _assertEntriesLatched(vaultAddr);

        // The stranded funds come back as a plain transfer and accrue to alice.
        strategy.unbrick();
        vm.prank(address(strategy));
        underlying.transfer(vaultAddr, ALLOCATED);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), DEPOSIT, "alice keeps the returned funds");

        vm.prank(admin);
        IVaultCoreRecovery(vaultAddr).clearManagerSwapLatch();
        assertEq(vault.maxDeposit(bob), type(uint256).max, "entries reopen once cleared");
        vm.prank(bob);
        assertEq(vault.deposit(1e18, bob), 1e18, "bob priced on the full NAV");
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), DEPOSIT, "alice not diluted");
    }

    /// @notice A swap away from an unlatched manager whose strategies still hold funds strands those funds just
    ///         as a force removal does, so it latches too.
    function test_ManagerSwap_FundedManager_Latches() public {
        assertFalse(mgr.depositsLatched(), "old manager unlatched");
        assertEq(mgr.totalAllocated(), ALLOCATED, "old manager holds funds");

        address freshMgr = _deployStrategyManager(admin);
        vm.expectEmit(true, false, false, false, vaultAddr);
        emit IVaultCoreRecovery.ManagerSwapLatchSet(diamond);
        vm.expectEmit(true, false, false, false, vaultAddr);
        emit IVaultCore.StrategyManagerSet(freshMgr);
        vm.prank(admin);
        vault.setStrategyManager(freshMgr);

        assertEq(vault.totalAssets(), IDLE, "stranded funds left the NAV");
        _assertEntriesLatched(vaultAddr);
    }

    /// @notice Rotating out a manager that verifiably holds nothing and is unlatched latches nothing.
    function test_ManagerSwap_EmptyManager_DoesNotLatch() public {
        _drainStrategy();

        vm.recordLogs();
        _swapToFreshManager();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != IVaultCoreRecovery.ManagerSwapLatchSet.selector, "no latch event");
        }
        assertFalse(IVaultCoreRecovery(vaultAddr).managerSwapLatched(), "not latched");
        assertEq(vault.maxDeposit(bob), type(uint256).max, "maxDeposit open");
        assertEq(_deposit(bob, 1e18), 1e18, "deposit open");
    }

    /// @notice The first `setStrategyManager` (no previous manager) and re-setting the same manager latch nothing.
    function test_ManagerSwap_FirstSetAndSameManager_DoNotLatch() public {
        assertFalse(IVaultCoreRecovery(vaultAddr).managerSwapLatched(), "first set did not latch");
        vm.prank(admin);
        vault.setStrategyManager(diamond);
        assertFalse(IVaultCoreRecovery(vaultAddr).managerSwapLatched(), "same manager did not latch");
        assertEq(vault.totalAssets(), DEPOSIT, "nothing left the NAV");
    }

    /// @notice An old manager whose latch read fails (no `depositsLatched()` selector) counts as latched: it
    ///         cannot show that nothing is stranded.
    function test_ManagerSwap_FailedLatchRead_Latches() public {
        _drainStrategy();
        LegacyManager legacy = new LegacyManager();
        vm.prank(admin);
        vault.setStrategyManager(address(legacy));
        assertFalse(IVaultCoreRecovery(vaultAddr).managerSwapLatched(), "drained manager released cleanly");

        _swapToFreshManager();
        assertTrue(IVaultCoreRecovery(vaultAddr).managerSwapLatched(), "failed latch read latches");
        _assertEntriesLatched(vaultAddr);
    }

    /// @notice An old manager whose `totalAllocated()` burns all its gas cannot block the swap; the failed read
    ///         latches.
    function test_ManagerSwap_GasBurningRead_DoesNotBlock() public {
        _drainStrategy();
        GasBurnManager burner = new GasBurnManager();
        vm.prank(admin);
        vault.setStrategyManager(address(burner));

        address freshMgr = _deployStrategyManager(admin);
        vm.prank(admin);
        vault.setStrategyManager{gas: 5_000_000}(freshMgr);
        assertEq(vault.strategyManager(), freshMgr, "swap went through");
        assertTrue(IVaultCoreRecovery(vaultAddr).managerSwapLatched(), "failed read latches");
    }

    /// @notice A `depositsLatched()` answer shorter than a word reads as unlatched while that manager is
    ///         configured, but a swap away from it latches: it cannot show that nothing is stranded.
    function test_ManagerSwap_ShortLatchRead_Latches() public {
        _drainStrategy();
        ShortLatchReadManager shortMgr = new ShortLatchReadManager();
        vm.prank(admin);
        vault.setStrategyManager(address(shortMgr));
        assertFalse(IVaultCoreRecovery(vaultAddr).managerSwapLatched(), "drained manager released cleanly");
        assertEq(vault.maxDeposit(bob), type(uint256).max, "short latch read reads as unlatched");

        _swapToFreshManager();
        assertTrue(IVaultCoreRecovery(vaultAddr).managerSwapLatched(), "short latch read latches the swap");
        _assertEntriesLatched(vaultAddr);
    }

    /// @notice A `totalAllocated()` answer shorter than a word latches a swap away from that manager.
    function test_ManagerSwap_ShortAllocatedRead_Latches() public {
        _drainStrategy();
        ShortAllocatedReadManager shortMgr = new ShortAllocatedReadManager();
        vm.prank(admin);
        vault.setStrategyManager(address(shortMgr));
        assertFalse(IVaultCoreRecovery(vaultAddr).managerSwapLatched(), "drained manager released cleanly");

        _swapToFreshManager();
        assertTrue(IVaultCoreRecovery(vaultAddr).managerSwapLatched(), "short allocation read latches the swap");
        _assertEntriesLatched(vaultAddr);
    }

    /// @notice The vault latch survives later swaps, including one away from a manager that held nothing.
    function test_ManagerSwapLatch_SurvivesLaterSwaps() public {
        _swapToFreshManager(); // strands ALLOCATED: latched
        _swapToFreshManager(); // the fresh manager held nothing
        assertTrue(IVaultCoreRecovery(vaultAddr).managerSwapLatched(), "latch held across the second swap");
        _assertEntriesLatched(vaultAddr);
    }

    /// @notice Deposits open only when both latches are clear: clearing the vault latch while the configured
    ///         manager is itself latched keeps entries closed, now naming the manager.
    function test_ManagerSwapLatch_AndManagerLatch_BothMustClear() public {
        address freshMgr = _swapToFreshManager();
        StrategyManager fresh = StrategyManager(freshMgr);
        NavStrategy next = new NavStrategy(underlying);
        vm.startPrank(admin);
        fresh.setVault(vaultAddr);
        fresh.addStrategy(address(next), 5_000);
        vm.stopPrank();
        next.brick();
        vm.prank(admin);
        fresh.removeStrategy(address(next)); // empty, but its read fails: the force removal latches the manager

        _assertEntriesLatched(vaultAddr);
        vm.prank(admin);
        IVaultCoreRecovery(vaultAddr).clearManagerSwapLatch();
        _assertEntriesLatched(freshMgr);

        vm.prank(admin);
        fresh.clearDepositLatch();
        assertEq(vault.maxDeposit(bob), type(uint256).max, "both clear: entries reopen");
    }

    /// @notice Only the vault's DEFAULT_ADMIN_ROLE clears; the clear emits ManagerSwapLatchCleared.
    function test_ManagerSwapLatch_Clear_AuthAndEvent() public {
        _swapToFreshManager();

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), bob, bytes32(0)
            )
        );
        IVaultCoreRecovery(vaultAddr).clearManagerSwapLatch();
        assertTrue(IVaultCoreRecovery(vaultAddr).managerSwapLatched(), "still latched");

        vm.expectEmit(true, false, false, false, vaultAddr);
        emit IVaultCoreRecovery.ManagerSwapLatchCleared(admin);
        vm.prank(admin);
        IVaultCoreRecovery(vaultAddr).clearManagerSwapLatch();
        assertFalse(IVaultCoreRecovery(vaultAddr).managerSwapLatched(), "cleared");
        assertEq(vault.maxMint(bob), type(uint256).max, "maxMint reopens");
    }

    /// @notice Clearing an unset vault latch reverts.
    function test_ManagerSwapLatch_ClearWhenNotSet_Reverts() public {
        vm.prank(admin);
        vm.expectRevert(IVaultCoreRecovery.VaultCoreManagerSwapLatchNotSet.selector);
        IVaultCoreRecovery(vaultAddr).clearManagerSwapLatch();
    }

    /// @notice The vault diamond advertises the recovery interface next to IVaultCore.
    function test_ManagerSwapLatch_SupportsInterface() public view {
        assertTrue(ERC165Facet(vaultAddr).supportsInterface(type(IVaultCore).interfaceId), "IVaultCore");
        assertTrue(ERC165Facet(vaultAddr).supportsInterface(type(IVaultCoreRecovery).interfaceId), "IVaultCoreRecovery");
    }

    /// @notice The manager diamond advertises the recovery interface next to IStrategyManager.
    function test_DepositLatch_SupportsInterface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IStrategyManager).interfaceId), "IStrategyManager");
        assertTrue(
            ERC165Facet(diamond).supportsInterface(type(IStrategyManagerRecovery).interfaceId),
            "IStrategyManagerRecovery"
        );
    }

    /// @notice A manager without the latch selector reads as unlatched: entries stay open.
    function test_DepositLatch_ManagerWithoutSelector_Unlatched() public {
        _drainStrategy(); // so the swap itself strands nothing and latches nothing
        LegacyManager legacy = new LegacyManager();
        vm.prank(admin);
        vault.setStrategyManager(address(legacy));

        assertEq(vault.maxDeposit(bob), type(uint256).max, "maxDeposit open");
        assertEq(vault.maxMint(bob), type(uint256).max, "maxMint open");
        assertGt(_deposit(bob, 1e18), 0, "deposit open");
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

    /// @notice #270 on the governed recipe: its {GovernedVault} deposit/mint wrappers and the VaultCore-served
    ///         `maxDeposit`/`maxMint` honor the latch, so the returned funds stay with the holders who stayed.
    function test_Governed_ForceRemoval_DonationSandwich_DepositsLatched() public {
        strategy.brick();
        mgr.removeStrategy(address(strategy)); // this test contract is the manager admin
        assertTrue(mgr.depositsLatched(), "latched");

        assertEq(vault.maxDeposit(bob), 0, "maxDeposit while latched");
        assertEq(vault.maxMint(bob), 0, "maxMint while latched");
        assertEq(vault.maxWithdraw(alice), IDLE, "exits open, capped at idle");

        asset.mint(bob, DEPOSIT);
        vm.startPrank(bob);
        asset.approve(vaultAddr, DEPOSIT);
        vm.expectRevert(abi.encodeWithSelector(IVaultCore.VaultCoreDepositsLatched.selector, address(mgr)));
        vault.deposit(DEPOSIT, bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultCore.VaultCoreDepositsLatched.selector, address(mgr)));
        vault.mint(DEPOSIT, bob);
        vm.stopPrank();

        strategy.unbrick();
        vm.prank(address(strategy));
        asset.transfer(vaultAddr, DEPOSIT - IDLE);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), DEPOSIT, "alice keeps the returned funds");

        mgr.clearDepositLatch();
        vm.prank(bob);
        assertEq(vault.deposit(DEPOSIT, bob), DEPOSIT, "bob priced on the full NAV");
    }

    /// @notice #305 on the governed recipe: a swap away from the latched manager (a passed proposal makes the
    ///         call) carries the latch to the vault, and only the vault's own admin role (governance) clears it.
    function test_Governed_ManagerSwap_CarriesLatch() public {
        strategy.brick();
        mgr.removeStrategy(address(strategy));

        DeployStrategyManager mgrDeployer = new DeployStrategyManager();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = mgrDeployer.buildCuts(address(this));
        Lattice fresh = new Lattice();
        fresh.initialize(cuts, init, initCalldata);
        vm.expectEmit(true, false, false, false, vaultAddr);
        emit IVaultCoreRecovery.ManagerSwapLatchSet(address(mgr));
        vm.prank(vaultAddr);
        vault.setStrategyManager(address(fresh));

        assertEq(vault.maxDeposit(bob), 0, "maxDeposit while latched");
        assertEq(vault.maxMint(bob), 0, "maxMint while latched");
        asset.mint(bob, DEPOSIT);
        vm.startPrank(bob);
        asset.approve(vaultAddr, DEPOSIT);
        vm.expectRevert(abi.encodeWithSelector(IVaultCore.VaultCoreDepositsLatched.selector, vaultAddr));
        vault.deposit(DEPOSIT, bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultCore.VaultCoreDepositsLatched.selector, vaultAddr));
        vault.mint(DEPOSIT, bob);
        vm.stopPrank();
        assertEq(vault.maxWithdraw(alice), IDLE, "exits open, capped at idle");

        vm.prank(vaultAddr);
        IVaultCoreRecovery(vaultAddr).clearManagerSwapLatch();
        vm.prank(bob);
        assertGt(vault.deposit(DEPOSIT, bob), 0, "entries reopen once governance clears");
    }

    /// @notice The governed recipe advertises the recovery interface next to IVaultCore.
    function test_Governed_ManagerSwapLatch_SupportsInterface() public view {
        assertTrue(ERC165Facet(vaultAddr).supportsInterface(type(IVaultCore).interfaceId), "IVaultCore");
        assertTrue(ERC165Facet(vaultAddr).supportsInterface(type(IVaultCoreRecovery).interfaceId), "IVaultCoreRecovery");
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
