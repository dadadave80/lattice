// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {StrategyManagerTestBase} from "@lattice-test/base/StrategyManagerTestBase.sol";
import {DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {StrategyManager} from "@lattice/defi/StrategyManager.sol";
import {REBALANCE_SHORTFALL_TOLERANCE} from "@lattice/defi/libraries/StrategyManagerLib.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {IStrategyManager} from "@lattice/interfaces/defi/IStrategyManager.sol";
import {IStrategyManagerRecovery} from "@lattice/interfaces/defi/IStrategyManagerRecovery.sol";
import {IVaultCore} from "@lattice/interfaces/defi/IVaultCore.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {Vm} from "forge-std/Vm.sol";

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
//          REVERTING STRATEGY (fail-closed / force-remove, #214)
//////////////////////////////////////////////////////////////////////////*//

/// @notice Strategy whose totalAssetsManaged() reverts once `brick()` is called.
/// @dev Used to verify that a bricked strategy makes `totalAllocated()` revert (so the vault
///      fails closed) and that `removeStrategy` force-removes it. It starts healthy because
///      `addStrategy` rejects a strategy whose balance read reverts.
contract RevertingStrategy {
    MockToken public token;
    bool public bricked;

    constructor(MockToken _token) {
        token = _token;
    }

    function brick() external {
        bricked = true;
    }

    function asset() external view returns (address) {
        return address(token);
    }

    function totalAssetsManaged() external view returns (uint256) {
        if (bricked) revert("strategy bricked");
        return 0;
    }

    function withdraw(uint256, address) external pure returns (uint256) {
        revert("strategy bricked");
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                         PARTIAL WITHDRAW STRATEGY (H-3)
//////////////////////////////////////////////////////////////////////////*//

/// @notice Strategy that only delivers a fraction of the requested withdrawal amount.
/// @dev Lossy mode writes off the full request while delivering only the fraction (slippage, an exit fee or a
///      lying strategy): rebalance() must revert (H-3). Honest mode writes off only what it delivered, like the
///      Lido buffer: a partial recall that rebalance() accepts (#221).
contract PartialWithdrawStrategy {
    MockToken public token;
    uint256 public managedBalance;
    /// @dev Fraction of the requested amount to actually deliver (0–100).
    uint8 public deliveryPct;
    /// @dev Whether the undelivered part of the request is also written off.
    bool public lossy;

    constructor(MockToken _token, uint8 _deliveryPct, bool _lossy) {
        token = _token;
        deliveryPct = _deliveryPct;
        lossy = _lossy;
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
        managedBalance -= lossy ? amount : actual;
        return actual;
    }
}

/// @notice Strategy that writes off the full request but delivers `lossWei` less (rounding-sized loss).
/// @dev Pins the boundary of the manager's fixed shortfall tolerance (#221).
contract WeiLossStrategy {
    MockToken public token;
    uint256 public managedBalance;
    uint256 public lossWei;

    constructor(MockToken _token, uint256 _lossWei) {
        token = _token;
        lossWei = _lossWei;
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
        token.transfer(to, amount - lossWei);
        managedBalance -= amount;
        return amount - lossWei;
    }
}

/// @notice Strategy that writes off and delivers `extraWei` more than requested, so a recall ends just under target.
/// @dev Used to verify that pass 2 does not hand a recall's rounding remainder straight back (#221).
contract OverDeliverStrategy {
    MockToken public token;
    uint256 public managedBalance;
    uint256 public extraWei;

    constructor(MockToken _token, uint256 _extraWei) {
        token = _token;
        extraWei = _extraWei;
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
        token.transfer(to, amount + extraWei);
        managedBalance -= amount + extraWei;
        return amount + extraWei;
    }
}

/// @notice Protocol-adapter-shaped strategy: advertises IProtocolAdapter via ERC-165 and exposes `deploy()`,
///         which moves its idle token balance into a notional position.
/// @dev Used to verify that rebalance() deploys an adapter's idle and survives a failing deploy (#221).
contract DeployableStrategy {
    MockToken public token;
    uint256 public deployed;
    uint256 public deployCalls;
    bool public deployReverts;

    constructor(MockToken _token) {
        token = _token;
    }

    function setDeployReverts(bool reverts) external {
        deployReverts = reverts;
    }

    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == type(IProtocolAdapter).interfaceId || id == 0x01ffc9a7;
    }

    function asset() external view returns (address) {
        return address(token);
    }

    function totalAssetsManaged() external view returns (uint256) {
        return token.balanceOf(address(this)) + deployed;
    }

    function deploy() external returns (uint256 amount) {
        if (deployReverts) revert IProtocolAdapter.ProtocolAdapterPaused();
        ++deployCalls;
        amount = token.balanceOf(address(this));
        deployed += amount;
        token.transfer(address(0xdead), amount); // the "protocol" now holds it
    }

    function withdraw(uint256 amount, address to) external returns (uint256) {
        token.transfer(to, amount);
        return amount;
    }
}

/// @notice Plain strategy with an empty fallback: an ERC-165 probe succeeds but returns no data.
contract FallbackStrategy is MockStrategy {
    constructor(MockToken _token) MockStrategy(_token) {}

    fallback() external {}
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
//                                 TESTS
//////////////////////////////////////////////////////////////////////////*//

/// @title StrategyManagerTest
/// @notice Exercises the StrategyManager facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployStrategyManager} script (see {StrategyManagerTestBase}) — every manager call routes through
///         the diamond's `delegatecall` dispatch, not a flattened inheritance mock. Admin gating is enforced by
///         the cut-in `AccessControl` facet; `supportsInterface` by the cut-in `ERC165Facet`. The vault,
///         strategy and token fixtures below are the collaborators the manager drives — NOT the facet under test.
contract StrategyManagerTest is StrategyManagerTestBase {
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

        diamond = _deployStrategyManager(admin);
        mgr = StrategyManager(diamond);
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

    /// @notice A strategy that already reports a balance cannot be added: it would step the NAV up on add (#214).
    function test_AddStrategy_NonzeroBalance_Reverts() public {
        strategyA.setManagedBalance(1);
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyManager.StrategyManagerStrategyNotEmpty.selector, address(strategyA), 1)
        );
        mgr.addStrategy(address(strategyA), 1000);
    }

    /// @notice A strategy whose balance read reverts cannot be added: it would freeze the vault on the spot.
    function test_AddStrategy_RevertingRead_Reverts() public {
        RevertingStrategy bricked = new RevertingStrategy(token);
        bricked.brick();
        vm.prank(admin);
        vm.expectRevert(bytes("strategy bricked"));
        mgr.addStrategy(address(bricked), 1000);
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

    /// @notice A strategy whose balance read reverts bricks totalAllocated(); removeStrategy force-removes it (#214).
    function test_RemoveStrategy_RevertingStrategy_ForceRemoves() public {
        RevertingStrategy bricked = new RevertingStrategy(token);
        vm.startPrank(admin);
        mgr.setVault(address(mockVault));
        mgr.addStrategy(address(bricked), 3000);
        mgr.addStrategy(address(strategyA), 2000);
        vm.stopPrank();
        strategyA.setManagedBalance(100e18);
        bricked.brick();

        vm.expectRevert(bytes("strategy bricked"));
        mgr.totalAllocated();

        vm.expectEmit(true, false, false, false, diamond);
        emit IStrategyManager.StrategyForceRemoved(address(bricked));
        vm.expectEmit(true, false, false, false, diamond);
        emit IStrategyManager.StrategyRemoved(address(bricked));
        vm.prank(admin);
        mgr.removeStrategy(address(bricked));

        assertEq(mgr.getStrategies().length, 1, "one strategy left");
        assertEq(mgr.getStrategies()[0], address(strategyA), "swap-and-pop kept strategyA");
        assertEq(mgr.totalTargetBps(), 2000, "bricked target released");
        assertEq(mgr.getStrategyTarget(address(bricked)), 0, "bricked target cleared");
        assertEq(mgr.totalAllocated(), 100e18, "totalAllocated readable again");
        assertTrue(mgr.depositsLatched(), "force removal latches deposits");
    }

    /// @notice A strategy whose code is gone (empty return data) also bricks totalAllocated() and is
    ///         force-removed: the removal check treats a read it cannot decode as failed.
    function test_RemoveStrategy_CodelessStrategy_ForceRemoves() public {
        address codeless = address(new RevertingStrategy(token));
        vm.prank(admin);
        mgr.addStrategy(codeless, 1000); // no vault set, so no asset check
        vm.etch(codeless, "");

        vm.expectRevert();
        mgr.totalAllocated();

        vm.expectEmit(true, false, false, false, diamond);
        emit IStrategyManager.StrategyForceRemoved(codeless);
        vm.prank(admin);
        mgr.removeStrategy(codeless);
        assertEq(mgr.getStrategies().length, 0);
    }

    /// @notice A healthy zero-balance removal is not reported as forced.
    function test_RemoveStrategy_ZeroBalance_NotForced() public {
        vm.prank(admin);
        mgr.addStrategy(address(strategyA), 5000);

        vm.recordLogs();
        vm.prank(admin);
        mgr.removeStrategy(address(strategyA));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != IStrategyManager.StrategyForceRemoved.selector, "not forced");
            assertTrue(logs[i].topics[0] != IStrategyManagerRecovery.DepositLatchSet.selector, "not latched");
        }
        assertFalse(mgr.depositsLatched(), "deposits stay open");
    }

    /// @notice Force removal stays admin-gated.
    function test_RemoveStrategy_RevertingStrategy_NonAdminReverts() public {
        RevertingStrategy bricked = new RevertingStrategy(token);
        vm.prank(admin);
        mgr.addStrategy(address(bricked), 1000);
        bricked.brick();

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, DEFAULT_ADMIN_ROLE
            )
        );
        mgr.removeStrategy(address(bricked));
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

    /// @notice rebalance reverts when a strategy underdelivers on withdraw (H-3): it writes off the 200 requested
    ///         but delivers 100, far beyond the fixed shortfall tolerance.
    function test_Rebalance_StrategyWithdrawShortfall_Reverts() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));

        // Deploy a strategy that only delivers 50% of the requested amount.
        PartialWithdrawStrategy partialStrat = new PartialWithdrawStrategy(token, 50, true);

        vm.prank(admin);
        mgr.addStrategy(address(partialStrat), 5000); // 50% target

        // Set strategy as over-allocated: holds 700, target is 500 of 1000 total.
        mockVault.setTotalAssets(1000e18);
        partialStrat.setManagedBalance(700e18);
        token.mint(address(partialStrat), 700e18);

        // Expected: released = 200e18, received = 100e18 → revert with shortfall.
        vm.expectRevert(
            abi.encodeWithSelector(
                IStrategyManager.StrategyManagerWithdrawShortfall.selector, address(partialStrat), 200e18, 100e18
            )
        );
        mgr.rebalance();
    }

    /// @dev Registers `strategy` at a 50% target, over-allocated at 700 of a 1000 NAV.
    function _overAllocate(address strategy) internal {
        vm.prank(admin);
        mgr.setVault(address(mockVault));
        vm.prank(admin);
        mgr.addStrategy(strategy, 5000);
        mockVault.setTotalAssets(1000e18);
        token.mint(strategy, 700e18);
    }

    /// @notice #221: a recall that loses at most the fixed tolerance (rounding) completes.
    function test_Rebalance_ShortfallAtTolerance_Succeeds() public {
        WeiLossStrategy s = new WeiLossStrategy(token, REBALANCE_SHORTFALL_TOLERANCE);
        _overAllocate(address(s));
        s.setManagedBalance(700e18);

        mgr.rebalance();
        assertEq(token.balanceOf(address(mockVault)), 200e18 - REBALANCE_SHORTFALL_TOLERANCE, "vault received");
        assertEq(s.managedBalance(), 500e18, "strategy at target");
    }

    /// @notice #221: one wei of loss past the fixed tolerance still reverts (H-3 kept).
    function test_Rebalance_ShortfallAboveTolerance_Reverts() public {
        WeiLossStrategy s = new WeiLossStrategy(token, REBALANCE_SHORTFALL_TOLERANCE + 1);
        _overAllocate(address(s));
        s.setManagedBalance(700e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IStrategyManager.StrategyManagerWithdrawShortfall.selector,
                address(s),
                200e18,
                200e18 - REBALANCE_SHORTFALL_TOLERANCE - 1
            )
        );
        mgr.rebalance();
    }

    /// @notice #221: an honest partial recall (the strategy still reports what it could not deliver, as the
    ///         Lido buffer does) completes and is reported, instead of bricking every rebalance.
    function test_Rebalance_HonestPartialRecall_Completes() public {
        PartialWithdrawStrategy s = new PartialWithdrawStrategy(token, 50, false);
        _overAllocate(address(s));
        s.setManagedBalance(700e18);

        vm.expectEmit(true, false, false, true, address(mgr));
        emit IStrategyManager.StrategyPartiallyRecalled(address(s), 200e18, 100e18);
        mgr.rebalance();

        assertEq(token.balanceOf(address(mockVault)), 100e18, "vault received the partial recall");
        assertEq(s.managedBalance(), 600e18, "the rest stays reported in the strategy");
    }

    /// @notice #221 value-loss semantics: a recall that delivers nothing while the strategy still reports its whole
    ///         balance lost no value, so it completes as a zero partial recall (the Lido buffer when empty, a
    ///         UniswapV3 position with no token0 left). Only a drop in reported balance beyond what the vault
    ///         received reverts; a strategy that lies about its balance is outside the trust model.
    function test_Rebalance_ZeroDelivery_BalanceUnchanged_IsPartialRecall() public {
        PartialWithdrawStrategy s = new PartialWithdrawStrategy(token, 0, false);
        _overAllocate(address(s));
        s.setManagedBalance(700e18);

        vm.expectEmit(true, false, false, true, address(mgr));
        emit IStrategyManager.StrategyPartiallyRecalled(address(s), 200e18, 0);
        mgr.rebalance();

        assertEq(token.balanceOf(address(mockVault)), 0, "nothing received");
        assertEq(s.managedBalance(), 700e18, "balance still reported");
    }

    /// @notice #221: a strategy recalled in pass 1 that ends a wei under target is not topped up by pass 2, which
    ///         would hand the recall's rounding remainder straight back.
    function test_Rebalance_RecalledStrategy_NotToppedUpInPass2() public {
        OverDeliverStrategy s = new OverDeliverStrategy(token, 1);
        _overAllocate(address(s));
        token.mint(address(s), 1);
        s.setManagedBalance(700e18);

        mgr.rebalance();

        assertEq(s.managedBalance(), 500e18 - 1, "recall ends a wei under target");
        assertEq(token.balanceOf(address(mockVault)), 200e18 + 1, "pass 2 allocates nothing back");
        assertEq(token.balanceOf(address(s)), 500e18, "strategy holds only what the recall left");
    }

    /// @notice #221: pass 2 allocates from the vault's actual idle, not the `vaultTotal` snapshot, so a partial
    ///         recall cannot make an allocation overdraw the vault.
    function test_Rebalance_PartialRecall_AllocatesFromActualIdle() public {
        PartialWithdrawStrategy over = new PartialWithdrawStrategy(token, 50, false);
        vm.prank(admin);
        mgr.setVault(address(mockVault));
        vm.startPrank(admin);
        mgr.addStrategy(address(over), 4000); // target 400
        mgr.addStrategy(address(strategyA), 6000); // target 600
        vm.stopPrank();

        // NAV 1000 = 200 vault idle + 800 in `over`. `over` can only return half of its 400 excess.
        mockVault.setTotalAssets(1000e18);
        token.mint(address(mockVault), 200e18);
        token.mint(address(over), 800e18);
        over.setManagedBalance(800e18);

        mgr.rebalance();

        assertEq(token.balanceOf(address(strategyA)), 400e18, "allocation capped at the 400 actually idle");
        assertEq(token.balanceOf(address(mockVault)), 0, "vault idle fully allocated, never overdrawn");
    }

    /// @notice #221: rebalance deploys a protocol adapter's idle after allocating to it.
    function test_Rebalance_DeploysAdapterIdle() public {
        DeployableStrategy s = new DeployableStrategy(token);
        vm.prank(admin);
        mgr.setVault(address(mockVault));
        vm.prank(admin);
        mgr.addStrategy(address(s), 5000);
        token.mint(address(mockVault), 1000e18);
        mockVault.setTotalAssets(1000e18);

        mgr.rebalance();

        assertEq(s.deployCalls(), 1, "deployed once");
        assertEq(s.deployed(), 500e18, "the allocation was deployed");
        assertEq(token.balanceOf(address(s)), 0, "no idle left in the adapter");
        assertEq(s.totalAssetsManaged(), 500e18, "NAV unchanged by the deploy");
    }

    /// @notice #221: a failing adapter deploy (e.g. paused protocol) is reported and never bricks rebalance.
    function test_Rebalance_FailingDeploy_DoesNotRevert() public {
        DeployableStrategy s = new DeployableStrategy(token);
        s.setDeployReverts(true);
        vm.prank(admin);
        mgr.setVault(address(mockVault));
        vm.prank(admin);
        mgr.addStrategy(address(s), 5000);
        token.mint(address(mockVault), 1000e18);
        mockVault.setTotalAssets(1000e18);

        vm.expectEmit(true, false, false, true, address(mgr));
        emit IStrategyManager.StrategyDeployFailed(
            address(s), abi.encodeWithSelector(IProtocolAdapter.ProtocolAdapterPaused.selector)
        );
        mgr.rebalance();

        assertEq(token.balanceOf(address(s)), 500e18, "allocation stays idle (and counted) in the adapter");
    }

    /// @notice #221: a strategy that does not advertise IProtocolAdapter is never sent `deploy()`.
    function test_Rebalance_PlainStrategy_NotDeployed() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));
        vm.prank(admin);
        mgr.addStrategy(address(strategyA), 5000);
        token.mint(address(mockVault), 1000e18);
        mockVault.setTotalAssets(1000e18);

        vm.recordLogs();
        mgr.rebalance();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != IStrategyManager.StrategyDeployFailed.selector, "no deploy attempted");
        }
        assertEq(token.balanceOf(address(strategyA)), 500e18, "allocated");
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
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IStrategyManager).interfaceId));
    }

    /// @notice StrategyManager registers the deposit-latch recovery interface (#270).
    function test_SupportsInterface_IStrategyManagerRecovery() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IStrategyManagerRecovery).interfaceId));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //              #245: MUTATION PILOT REGRESSIONS (test/README.md)
    //////////////////////////////////////////////////////////////////////////*//

    function test_AddStrategy_ZeroAddress_Reverts() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IStrategyManager.StrategyManagerInvalidStrategy.selector, address(0)));
        mgr.addStrategy(address(0), 1000);
    }

    /// @notice Removing a middle strategy keeps every other index right: later removals and re-adds still work.
    function test_RemoveStrategy_MiddleThenLast_KeepsIndexes() public {
        MockStrategy strategyC = new MockStrategy(token);
        vm.startPrank(admin);
        mgr.setVault(address(mockVault));
        mgr.addStrategy(address(strategyA), 1000);
        mgr.addStrategy(address(strategyB), 2000);
        mgr.addStrategy(address(strategyC), 3000);

        mgr.removeStrategy(address(strategyB));
        address[] memory list = mgr.getStrategies();
        assertEq(list.length, 2);
        assertEq(list[0], address(strategyA));
        assertEq(list[1], address(strategyC));

        mgr.removeStrategy(address(strategyC));
        list = mgr.getStrategies();
        assertEq(list.length, 1);
        assertEq(list[0], address(strategyA));

        mgr.addStrategy(address(strategyB), 2000);
        vm.stopPrank();
        list = mgr.getStrategies();
        assertEq(list.length, 2);
        assertEq(list[1], address(strategyB));
        assertEq(mgr.totalTargetBps(), 3000);
    }

    function test_UpdateStrategyTarget_NonAdmin_Reverts() public {
        vm.prank(admin);
        mgr.addStrategy(address(strategyA), 1000);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, DEFAULT_ADMIN_ROLE
            )
        );
        mgr.updateStrategyTarget(address(strategyA), 2000);
    }

    function test_UpdateStrategyTarget_NotFound_Reverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyManager.StrategyManagerStrategyNotFound.selector, address(strategyA))
        );
        mgr.updateStrategyTarget(address(strategyA), 1000);
    }

    /// @notice The total moves by exactly the target's change, with other strategies' targets in it.
    function test_UpdateStrategyTarget_TotalMovesByTheDifference() public {
        vm.startPrank(admin);
        mgr.addStrategy(address(strategyA), 3000);
        mgr.addStrategy(address(strategyB), 4000);
        mgr.updateStrategyTarget(address(strategyA), 1000);
        vm.stopPrank();
        assertEq(mgr.totalTargetBps(), 5000);
    }

    /// @notice A strategy recalled at index >= 2 is still skipped in pass 2, and the ones before it are not.
    function test_Rebalance_RecalledThirdStrategy_OthersStillAllocated() public {
        OverDeliverStrategy s = new OverDeliverStrategy(token, 1);
        vm.startPrank(admin);
        mgr.setVault(address(mockVault));
        mgr.addStrategy(address(strategyA), 2000); // target 200
        mgr.addStrategy(address(strategyB), 2000); // target 200
        mgr.addStrategy(address(s), 5000); // target 500
        vm.stopPrank();

        mockVault.setTotalAssets(1000e18);
        token.mint(address(mockVault), 400e18);
        token.mint(address(s), 701e18);
        s.setManagedBalance(700e18);

        mgr.rebalance();

        assertEq(token.balanceOf(address(strategyA)), 200e18, "A allocated");
        assertEq(token.balanceOf(address(strategyB)), 200e18, "B allocated");
        assertEq(s.managedBalance(), 500e18 - 1, "recalled strategy not topped up");
        assertEq(token.balanceOf(address(mockVault)), 200e18 + 1, "vault keeps the recall's remainder");
    }

    /// @notice Pass 2 tracks the idle it hands out: once it runs out, later strategies wait.
    function test_Rebalance_IdleRunsOut_LaterStrategyWaits() public {
        vm.startPrank(admin);
        mgr.setVault(address(mockVault));
        mgr.addStrategy(address(strategyA), 5000);
        mgr.addStrategy(address(strategyB), 5000);
        vm.stopPrank();

        mockVault.setTotalAssets(4000e18); // targets 2000 each
        token.mint(address(mockVault), 1000e18);

        mgr.rebalance();

        assertEq(token.balanceOf(address(strategyA)), 1000e18);
        assertEq(token.balanceOf(address(strategyB)), 0);
        assertEq(token.balanceOf(address(mockVault)), 0);
    }

    /// @notice Pass 2 allocates only the deficit `target - current`.
    function test_Rebalance_PartlyFundedStrategy_GetsOnlyTheDeficit() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));
        vm.prank(admin);
        mgr.addStrategy(address(strategyA), 5000); // target 500
        strategyA.setManagedBalance(200e18);
        mockVault.setTotalAssets(1000e18);
        token.mint(address(mockVault), 1000e18);

        mgr.rebalance();

        assertEq(token.balanceOf(address(strategyA)), 300e18);
    }

    /// @notice A strategy exactly at target is not sent a zero allocation.
    function test_Rebalance_StrategyAtTarget_NoAllocationCall() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));
        vm.prank(admin);
        mgr.addStrategy(address(strategyA), 5000);
        strategyA.setManagedBalance(500e18);
        mockVault.setTotalAssets(1000e18);
        token.mint(address(mockVault), 500e18);

        vm.expectCall(address(mockVault), abi.encodeWithSelector(MockVault.allocateToStrategy.selector), 0);
        mgr.rebalance();
    }

    /// @notice A recall that delivers everything asked is not reported as partial.
    function test_Rebalance_FullRecall_NotReportedPartial() public {
        vm.prank(admin);
        mgr.setVault(address(mockVault));
        vm.prank(admin);
        mgr.addStrategy(address(strategyA), 5000);
        mockVault.setTotalAssets(1000e18);
        strategyA.setManagedBalance(700e18);
        token.mint(address(strategyA), 700e18);

        vm.recordLogs();
        mgr.rebalance();
        _assertNoLog(IStrategyManager.StrategyPartiallyRecalled.selector);
        assertEq(token.balanceOf(address(mockVault)), 200e18);
    }

    /// @notice An adapter holding no idle is not sent `deploy()`.
    function test_Rebalance_AdapterWithoutIdle_NotDeployed() public {
        DeployableStrategy s = new DeployableStrategy(token);
        vm.prank(admin);
        mgr.setVault(address(mockVault));
        vm.prank(admin);
        mgr.addStrategy(address(s), 0);
        mockVault.setTotalAssets(1000e18);

        mgr.rebalance();
        assertEq(s.deployCalls(), 0);
    }

    /// @notice A successful deploy reports no failure.
    function test_Rebalance_SuccessfulDeploy_ReportsNoFailure() public {
        DeployableStrategy s = new DeployableStrategy(token);
        vm.prank(admin);
        mgr.setVault(address(mockVault));
        vm.prank(admin);
        mgr.addStrategy(address(s), 5000);
        token.mint(address(mockVault), 1000e18);
        mockVault.setTotalAssets(1000e18);

        vm.recordLogs();
        mgr.rebalance();
        _assertNoLog(IStrategyManager.StrategyDeployFailed.selector);
        assertEq(s.deployCalls(), 1);
    }

    /// @notice A strategy whose ERC-165 probe returns no data is treated as a plain strategy, not a revert.
    function test_Rebalance_EmptyProbeReply_Skipped() public {
        FallbackStrategy s = new FallbackStrategy(token);
        vm.prank(admin);
        mgr.setVault(address(mockVault));
        vm.prank(admin);
        mgr.addStrategy(address(s), 0);
        mockVault.setTotalAssets(1000e18);
        token.mint(address(s), 10e18);

        vm.recordLogs();
        mgr.rebalance();
        _assertNoLog(IStrategyManager.StrategyDeployFailed.selector);
    }

    function _assertNoLog(bytes32 sig) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != sig, "unexpected event");
        }
    }
}
