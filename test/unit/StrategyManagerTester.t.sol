// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {StrategyManager} from "@lattice/defi/StrategyManager.sol";
import {StrategyManagerLib} from "@lattice/defi/libraries/StrategyManagerLib.sol";
import {IStrategyManager} from "@lattice/interfaces/defi/IStrategyManager.sol";
import {IVaultCore} from "@lattice/interfaces/defi/IVaultCore.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                          MOCK UNDERLYING ERC20
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal ERC-20 used by mock vault and strategies.
contract MockToken {
    string public name = "Mock Token";
    string public symbol = "MTK";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                              MOCK VAULT
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal vault mock: implements asset() and totalAssets() and
///         allocateToStrategy() (which transfers token to strategy).
contract MockVault {
    MockToken public token;
    uint256 public mockedTotalAssets;

    constructor(MockToken _token) {
        token = _token;
    }

    function asset() external view returns (address) {
        return address(token);
    }

    function totalAssets() external view returns (uint256) {
        return mockedTotalAssets > 0 ? mockedTotalAssets : token.balanceOf(address(this));
    }

    function setTotalAssets(uint256 amount) external {
        mockedTotalAssets = amount;
    }

    /// @dev Simulates IVaultCore.allocateToStrategy by transferring tokens.
    function allocateToStrategy(address strategy, uint256 amount) external {
        token.transfer(strategy, amount);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                              MOCK STRATEGY
//////////////////////////////////////////////////////////////////////////*//

/// @notice Mock strategy: reports a settable balance and accepts withdrawals.
contract MockStrategy {
    MockToken public token;
    uint256 public managedBalance;

    constructor(MockToken _token) {
        token = _token;
    }

    function asset() external view returns (address) {
        return address(token);
    }

    function setManagedBalance(uint256 amount) external {
        managedBalance = amount;
    }

    function totalAssetsManaged() external view returns (uint256) {
        return managedBalance;
    }

    function withdraw(uint256 amount, address to) external returns (uint256) {
        // Simulate returning assets to vault.
        token.transfer(to, amount);
        managedBalance -= amount;
        return amount;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//              REVERTING STRATEGY (T-1: DoS resilience test)
//////////////////////////////////////////////////////////////////////////*//

/// @notice Strategy whose totalAssetsManaged() always reverts.
/// @dev Used to verify that the VaultCore's staticcall guard keeps the vault
///      operational even when a registered strategy is bricked.
contract RevertingStrategy {
    MockToken public token;

    constructor(MockToken _token) {
        token = _token;
    }

    function asset() external view returns (address) {
        return address(token);
    }

    function totalAssetsManaged() external pure returns (uint256) {
        revert("strategy bricked");
    }

    function withdraw(uint256, address) external pure returns (uint256) {
        revert("strategy bricked");
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                         PARTIAL WITHDRAW STRATEGY (H-3)
//////////////////////////////////////////////////////////////////////////*//

/// @notice Strategy that only delivers a fraction of the requested withdrawal amount.
/// @dev Used to verify that rebalance() reverts on underdelivery (H-3).
contract PartialWithdrawStrategy {
    MockToken public token;
    uint256 public managedBalance;
    /// @dev Fraction of the requested amount to actually deliver (0–100).
    uint8 public deliveryPct;

    constructor(MockToken _token, uint8 _deliveryPct) {
        token = _token;
        deliveryPct = _deliveryPct;
    }

    function asset() external view returns (address) {
        return address(token);
    }

    function setManagedBalance(uint256 amount) external {
        managedBalance = amount;
    }

    function totalAssetsManaged() external view returns (uint256) {
        return managedBalance;
    }

    function withdraw(uint256 amount, address to) external returns (uint256) {
        uint256 actual = (amount * deliveryPct) / 100;
        if (actual > 0) token.transfer(to, actual);
        managedBalance -= actual;
        return actual;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                       REENTRANT STRATEGY (M-2 reentrancy test)
//////////////////////////////////////////////////////////////////////////*//

/// @notice Strategy that re-enters rebalance() during its withdraw() call.
/// @dev Used to verify that the reentrancy guard on rebalance() blocks the attack.
contract ReentrantStrategy {
    MockToken public token;
    uint256 public managedBalance;
    address public manager;

    constructor(MockToken _token, address _manager) {
        token = _token;
        manager = _manager;
    }

    function asset() external view returns (address) {
        return address(token);
    }

    function setManagedBalance(uint256 amount) external {
        managedBalance = amount;
    }

    function totalAssetsManaged() external view returns (uint256) {
        return managedBalance;
    }

    function withdraw(uint256 amount, address to) external returns (uint256) {
        // Attempt to re-enter rebalance() while a rebalance is already in progress.
        // The reentrancy guard must block this call.
        IStrategyManager(manager).rebalance();
        token.transfer(to, amount);
        managedBalance -= amount;
        return amount;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                       MOCK STRATEGY MANAGER CONTRACT
//////////////////////////////////////////////////////////////////////////*//

/// @notice StrategyManager mock that exposes init.
contract MockStrategyManagerContract is StrategyManager {
    function initialize(address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        StrategyManagerLib.__StrategyManager_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                 TESTS
//////////////////////////////////////////////////////////////////////////*//

/// @title StrategyManagerTester
/// @notice Tests for the StrategyManager three-layer module.
contract StrategyManagerTester is Test {
    MockStrategyManagerContract mgr;
    MockToken token;
    MockVault mockVault;
    MockStrategy strategyA;
    MockStrategy strategyB;

    address admin = address(0xAD);
    address user = address(0xA1);

    function setUp() public {
        token = new MockToken();
        mockVault = new MockVault(token);
        strategyA = new MockStrategy(token);
        strategyB = new MockStrategy(token);

        mgr = new MockStrategyManagerContract();
        vm.prank(admin);
        mgr.initialize(admin);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           SET VAULT TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Admin can set vault.
    function test_SetVault_Admin() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));
        assertEq(mgr.vault(), address(mockVault));
    }

    /// @notice Non-admin cannot set vault.
    function test_SetVault_NonAdmin_Reverts() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, DEFAULT_ADMIN_ROLE
            )
        );
        mgr.setVault(address(mockVault));
    }

    /// @notice setVault(address(0)) reverts.
    function test_SetVault_ZeroAddress_Reverts() public {
        vm.prank(admin);
        vm.expectRevert(IStrategyManager.StrategyManagerVaultNotSet.selector);
        mgr.setVault(address(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          ADD STRATEGY TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Admin can add a strategy.
    function test_AddStrategy_Admin() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        vm.prank(admin);
        mgr.addStrategy(address(strategyA), 5000);

        assertEq(mgr.getStrategies().length, 1);
        assertEq(mgr.getStrategyTarget(address(strategyA)), 5000);
        assertEq(mgr.totalTargetBps(), 5000);
    }

    /// @notice Non-admin cannot add a strategy.
    function test_AddStrategy_NonAdmin_Reverts() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, DEFAULT_ADMIN_ROLE
            )
        );
        mgr.addStrategy(address(strategyA), 5000);
    }

    /// @notice Adding a strategy with total bps > 10000 reverts.
    function test_AddStrategy_ExceedsTotalBps_Reverts() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        vm.prank(admin);
        mgr.addStrategy(address(strategyA), 6000);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyManager.StrategyManagerInvalidAllocation.selector, uint256(11_000))
        );
        mgr.addStrategy(address(strategyB), 5000);
    }

    /// @notice Adding a strategy whose asset doesn't match vault asset reverts.
    function test_AddStrategy_AssetMismatch_Reverts() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        // Deploy a strategy with a different token.
        MockToken otherToken = new MockToken();
        MockStrategy badStrategy = new MockStrategy(otherToken);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyManager.StrategyManagerAssetMismatch.selector, address(badStrategy))
        );
        mgr.addStrategy(address(badStrategy), 1000);
    }

    /// @notice Adding a duplicate strategy reverts.
    function test_AddStrategy_Duplicate_Reverts() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        vm.prank(admin);
        mgr.addStrategy(address(strategyA), 3000);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyManager.StrategyManagerStrategyAlreadyAdded.selector, address(strategyA))
        );
        mgr.addStrategy(address(strategyA), 1000);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         REMOVE STRATEGY TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Remove strategy uses swap-and-pop; array and indexes are correct after removal.
    function test_RemoveStrategy_SwapAndPop() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        vm.startPrank(admin);
        mgr.addStrategy(address(strategyA), 3000);
        mgr.addStrategy(address(strategyB), 2000);
        vm.stopPrank();

        assertEq(mgr.getStrategies().length, 2);
        assertEq(mgr.totalTargetBps(), 5000);

        vm.prank(admin);
        mgr.removeStrategy(address(strategyA));

        assertEq(mgr.getStrategies().length, 1);
        assertEq(mgr.getStrategies()[0], address(strategyB));
        assertEq(mgr.totalTargetBps(), 2000);
        assertEq(mgr.getStrategyTarget(address(strategyA)), 0);
    }

    /// @notice removeStrategy reverts when the strategy still holds live assets (M-3).
    function test_RemoveStrategy_WithLiveAllocation_Reverts() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        vm.prank(admin);
        mgr.addStrategy(address(strategyA), 5000);

        // Give the strategy a live balance.
        strategyA.setManagedBalance(500e18);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStrategyManager.StrategyManagerStrategyStillAllocated.selector, address(strategyA), 500e18
            )
        );
        mgr.removeStrategy(address(strategyA));
    }

    /// @notice removeStrategy succeeds when the strategy has zero live assets (M-3).
    function test_RemoveStrategy_WithZeroBalance_Succeeds() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        vm.prank(admin);
        mgr.addStrategy(address(strategyA), 5000);

        // Ensure zero balance before removal.
        strategyA.setManagedBalance(0);

        vm.prank(admin);
        mgr.removeStrategy(address(strategyA)); // should not revert

        assertEq(mgr.getStrategies().length, 0);
    }

    /// @notice Removing a non-existent strategy reverts.
    function test_RemoveStrategy_NotFound_Reverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyManager.StrategyManagerStrategyNotFound.selector, address(strategyA))
        );
        mgr.removeStrategy(address(strategyA));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     UPDATE STRATEGY TARGET TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Admin can update strategy target within bounds.
    function test_UpdateStrategyTarget_WithinBounds() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        vm.prank(admin);
        mgr.addStrategy(address(strategyA), 3000);

        vm.prank(admin);
        mgr.updateStrategyTarget(address(strategyA), 5000);

        assertEq(mgr.getStrategyTarget(address(strategyA)), 5000);
        assertEq(mgr.totalTargetBps(), 5000);
    }

    /// @notice Updating a strategy target that would exceed 10000 reverts.
    function test_UpdateStrategyTarget_ExceedsBps_Reverts() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        vm.startPrank(admin);
        mgr.addStrategy(address(strategyA), 5000);
        mgr.addStrategy(address(strategyB), 3000);
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyManager.StrategyManagerInvalidAllocation.selector, uint256(11_000))
        );
        mgr.updateStrategyTarget(address(strategyA), 8000);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         TOTAL ALLOCATED TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice totalAllocated sums all strategy balances.
    function test_TotalAllocated_SumsBalances() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        vm.startPrank(admin);
        mgr.addStrategy(address(strategyA), 5000);
        mgr.addStrategy(address(strategyB), 3000);
        vm.stopPrank();

        strategyA.setManagedBalance(400e18);
        strategyB.setManagedBalance(200e18);

        assertEq(mgr.totalAllocated(), 600e18);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           HARVEST TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice harvest emits Harvested event with total allocated.
    function test_Harvest_EmitsEvent() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        vm.prank(admin);
        mgr.addStrategy(address(strategyA), 5000);
        strategyA.setManagedBalance(300e18);

        vm.expectEmit(false, false, false, true);
        emit IStrategyManager.Harvested(300e18);
        mgr.harvest();
    }

    /// @notice harvest can be called by anyone.
    function test_Harvest_AnyoneCan_Call() public {
        vm.prank(user);
        mgr.harvest(); // should not revert
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          REBALANCE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice rebalance pushes assets to strategy when under-allocated.
    function test_Rebalance_UnderAllocated_AllocatesAssets() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        vm.prank(admin);
        mgr.addStrategy(address(strategyA), 5000); // 50% target

        // Vault holds 1000 tokens, strategy holds 0 → target = 500
        token.mint(address(mockVault), 1000e18);
        mockVault.setTotalAssets(1000e18);
        strategyA.setManagedBalance(0);

        // StrategyManager needs tokens in vault to allocate; grant it the manager role
        // by making mgr the "strategy manager" on the vault mock.
        // In our simplified MockVault.allocateToStrategy we just need to ensure token is available.

        vm.expectEmit(false, false, false, false);
        emit IStrategyManager.Rebalanced();
        mgr.rebalance();

        // strategy should have received 500 tokens
        assertEq(token.balanceOf(address(strategyA)), 500e18);
    }

    /// @notice rebalance withdraws excess from over-allocated strategy.
    function test_Rebalance_OverAllocated_WithdrawsAssets() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        vm.prank(admin);
        mgr.addStrategy(address(strategyA), 5000); // 50% target

        // Vault total = 1000, strategy manages 700 → over by 200
        mockVault.setTotalAssets(1000e18);
        strategyA.setManagedBalance(700e18);
        token.mint(address(strategyA), 700e18);

        mgr.rebalance();

        // strategy should have returned 200 to vault
        assertEq(strategyA.managedBalance(), 500e18);
        assertEq(token.balanceOf(address(mockVault)), 200e18);
    }

    /// @notice rebalance reverts if vault is not set.
    function test_Rebalance_VaultNotSet_Reverts() public {
        vm.expectRevert(IStrategyManager.StrategyManagerVaultNotSet.selector);
        mgr.rebalance();
    }

    /// @notice rebalance succeeds regardless of strategy registration order (M-1).
    /// @dev Over-allocated strategy B is registered AFTER under-allocated strategy A.
    ///      Without the two-pass fix, rebalancing A first would fail (no idle) because
    ///      B hasn't returned its excess yet. With two-pass, B's excess is recalled in
    ///      pass 1 before A is funded in pass 2.
    function test_Rebalance_OrderIndependent_TwoPass() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        // strategyA: 60% target. strategyB: 40% target. Total = 100%.
        vm.startPrank(admin);
        mgr.addStrategy(address(strategyA), 6000);
        mgr.addStrategy(address(strategyB), 4000);
        vm.stopPrank();

        // Vault total = 1000 tokens.
        // strategyA current = 0   → target = 600 → under-allocated by 600.
        // strategyB current = 800 → target = 400 → over-allocated by 400.
        // Vault idle = 200 (insufficient alone to fund strategyA's +600 deficit).
        mockVault.setTotalAssets(1000e18);
        strategyA.setManagedBalance(0);
        strategyB.setManagedBalance(800e18);
        token.mint(address(mockVault), 200e18);
        token.mint(address(strategyB), 800e18);

        // With single-pass: allocate strategyA (+600) would fail — vault only has 200 idle.
        // With two-pass: pass 1 recalls 400 from strategyB → vault has 600 idle → pass 2 funds strategyA.
        mgr.rebalance();

        assertApproxEqAbs(token.balanceOf(address(strategyA)), 600e18, 1, "stratA should hold 600");
        assertApproxEqAbs(strategyB.managedBalance(), 400e18, 1, "stratB should hold 400");
    }

    /// @notice rebalance is protected against reentrancy (M-2).
    /// @dev A malicious strategy that calls rebalance() from within its withdraw() must be blocked.
    function test_Rebalance_ReentrancyBlocked() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        // Register reentrant strategy as over-allocated.
        ReentrantStrategy reentrant = new ReentrantStrategy(token, address(mgr));

        vm.prank(admin);
        mgr.addStrategy(address(reentrant), 5000);

        mockVault.setTotalAssets(1000e18);
        reentrant.setManagedBalance(700e18);
        token.mint(address(reentrant), 700e18);

        // The outer rebalance triggers reentrant.withdraw(), which re-enters rebalance().
        // The inner rebalance() call must revert with ReentrancyGuardReentrantCall.
        // The outer rebalance() will then also revert (the inner revert propagates).
        vm.expectRevert();
        mgr.rebalance();
    }

    /// @notice rebalance reverts when a strategy underdelivers on withdraw (H-3).
    function test_Rebalance_StrategyWithdrawShortfall_Reverts() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        // Deploy a strategy that only delivers 50% of the requested amount.
        PartialWithdrawStrategy partialStrat = new PartialWithdrawStrategy(token, 50);

        vm.prank(admin);
        mgr.addStrategy(address(partialStrat), 5000); // 50% target

        // Set strategy as over-allocated: holds 700, target is 500 of 1000 total.
        mockVault.setTotalAssets(1000e18);
        partialStrat.setManagedBalance(700e18);
        token.mint(address(partialStrat), 700e18);

        // Expected: requested = 200e18, actual = 100e18 → revert with shortfall.
        vm.expectRevert(
            abi.encodeWithSelector(
                IStrategyManager.StrategyManagerWithdrawShortfall.selector, address(partialStrat), 200e18, 100e18
            )
        );
        mgr.rebalance();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     BOUNDARY / EDGE-CASE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice rebalance is a no-op when vault total is zero (zero allocation boundary).
    function test_Rebalance_ZeroVaultTotal_NoOp() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        vm.prank(admin);
        mgr.addStrategy(address(strategyA), 5000);

        mockVault.setTotalAssets(0);
        strategyA.setManagedBalance(0);

        // No tokens in vault or strategy; rebalance should succeed silently with no transfers.
        mgr.rebalance();

        assertEq(token.balanceOf(address(strategyA)), 0);
        assertEq(token.balanceOf(address(mockVault)), 0);
    }

    /// @notice Adding a strategy at exactly the strategy count cap reverts (L-2).
    function test_AddStrategy_AtMaxStrategies_Reverts() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        // Fill up to MAX_STRATEGIES (20) each with 0 bps (no allocation needed).
        for (uint256 i = 0; i < 20; ++i) {
            // Deploy a fresh mock strategy for each slot.
            MockStrategy s = new MockStrategy(token);
            vm.prank(admin);
            mgr.addStrategy(address(s), 0);
        }

        // The 21st addition must revert.
        MockStrategy overflow = new MockStrategy(token);
        vm.prank(admin);
        vm.expectRevert(IStrategyManager.StrategyManagerTooManyStrategies.selector);
        mgr.addStrategy(address(overflow), 0);
    }

    /// @notice rebalance with exact 100% allocation distributes all vault assets.
    function test_Rebalance_ExactFullAllocation() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        vm.startPrank(admin);
        mgr.addStrategy(address(strategyA), 5000); // 50%
        mgr.addStrategy(address(strategyB), 5000); // 50% — total 100%
        vm.stopPrank();

        // Vault holds 1000 tokens, no tokens in strategies.
        token.mint(address(mockVault), 1000e18);
        mockVault.setTotalAssets(1000e18);
        strategyA.setManagedBalance(0);
        strategyB.setManagedBalance(0);

        mgr.rebalance();

        assertApproxEqAbs(token.balanceOf(address(strategyA)), 500e18, 1, "stratA gets 50%");
        assertApproxEqAbs(token.balanceOf(address(strategyB)), 500e18, 1, "stratB gets 50%");
        assertApproxEqAbs(token.balanceOf(address(mockVault)), 0, 1, "vault idle ~0");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice StrategyManager registers its interface.
    function test_SupportsInterface_IStrategyManager() public view {
        assertTrue(mgr.supportsInterface(type(IStrategyManager).interfaceId));
    }
}
