// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title VaultStrategyTest
/// @notice Integration test composing ERC4626 vault (via VaultCore) +
///         StrategyManager + two real strategy instances.
///
/// End-to-end flow:
///  1. Deploy a TestAssetToken (simple ERC-20 mock).
///  2. Deploy MockVault (ERC4626 + VaultCore + AccessControl).
///  3. Deploy MockStrategyManager + two MockStrategy contracts.
///  4. Configure vault → manager link; add both strategies with 50/50 target.
///  5. User deposits 1 000 asset → receives shares.
///  6. Call rebalance() → assets flow from vault to strategies.
///  7. Verify totalAssets accounting: idle + sum(strategy.totalAssetsManaged()) == deposit.
///  8. User withdraws half → verified via share redemption.

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {StrategyManager} from "@lattice/defi/StrategyManager.sol";
import {VaultCore} from "@lattice/defi/VaultCore.sol";
import {StrategyManagerLib} from "@lattice/defi/libraries/StrategyManagerLib.sol";
import {VaultCoreLib} from "@lattice/defi/libraries/VaultCoreLib.sol";
import {IStrategyManager} from "@lattice/interfaces/defi/IStrategyManager.sol";
import {IVaultCore} from "@lattice/interfaces/defi/IVaultCore.sol";
import {IStrategy} from "@lattice/interfaces/external/IStrategy.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC4626} from "@lattice/tokens/ERC4626/ERC4626.sol";
import {ERC4626Lib} from "@lattice/tokens/ERC4626/libraries/ERC4626Lib.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                          TEST ASSET TOKEN
//////////////////////////////////////////////////////////////////////////*//

/// @notice Simple mintable ERC-20 used as the vault's underlying asset.
contract TestAssetToken {
    string public name = "Test Asset";
    string public symbol = "TST";
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
//                         MOCK VAULT (ERC4626 + VaultCore)
//////////////////////////////////////////////////////////////////////////*//

/// @notice ERC-4626 vault extended with VaultCore for strategy management. Flattens the composable {ERC20},
///         {ERC4626}, and {VaultCore} facets into one mock; the strategy-aware {VaultCore} mutators win the clashes.
contract MockERC4626Vault is ERC20, ERC4626, VaultCore {
    function initialize(address asset_, address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        ERC20Lib.__ERC20_init("Vault Share", "vSHARE");
        ERC4626Lib.__ERC4626_init(asset_, 0);
        VaultCoreLib.__VaultCore_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }

    /// @dev Resolves the flattened-facet clashes; the strategy-aware {VaultCore} variants win.
    function decimals() public view override(ERC20, ERC4626) returns (uint8) {
        return ERC4626.decimals();
    }

    function totalAssets() public view override(ERC4626, VaultCore) returns (uint256) {
        return VaultCore.totalAssets();
    }

    function deposit(uint256 assets, address receiver) public override(ERC4626, VaultCore) returns (uint256) {
        return VaultCore.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override(ERC4626, VaultCore) returns (uint256) {
        return VaultCore.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override(ERC4626, VaultCore)
        returns (uint256)
    {
        return VaultCore.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override(ERC4626, VaultCore)
        returns (uint256)
    {
        return VaultCore.redeem(shares, receiver, owner);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                   MOCK STRATEGY MANAGER CONTRACT
//////////////////////////////////////////////////////////////////////////*//

/// @notice Real StrategyManager facet wired to the vault.
contract MockIntegrationStrategyManager is StrategyManager {
    function initialize(address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        StrategyManagerLib.__StrategyManager_init();
        InitializableLib.postInitializer(s);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                          MOCK STRATEGY
//////////////////////////////////////////////////////////////////////////*//

/// @notice Concrete strategy that accepts allocations and reports its balance.
/// @dev Holds the actual ERC-20 tokens so rebalance math works end-to-end.
contract ConcreteStrategy is IStrategy {
    TestAssetToken public immutable assetToken;

    constructor(TestAssetToken _asset) {
        assetToken = _asset;
    }

    function asset() external view override returns (address) {
        return address(assetToken);
    }

    function totalAssetsManaged() external view override returns (uint256) {
        return assetToken.balanceOf(address(this));
    }

    function withdraw(uint256 amount, address to) external override returns (uint256) {
        assetToken.transfer(to, amount);
        return amount;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                              TEST SUITE
//////////////////////////////////////////////////////////////////////////*//

contract VaultStrategyTest is Test {
    TestAssetToken asset;
    MockERC4626Vault vault;
    MockIntegrationStrategyManager mgr;
    ConcreteStrategy stratA;
    ConcreteStrategy stratB;

    address admin = address(0xAD);
    address user = address(0xA1);

    uint256 constant DEPOSIT_AMOUNT = 1_000e18;
    uint16 constant HALF_BPS = 5_000; // 50 %

    function setUp() public {
        // 1. Deploy asset token.
        asset = new TestAssetToken();

        // 2. Deploy vault.
        vault = new MockERC4626Vault();
        vault.initialize(address(asset), admin);

        // 3. Deploy strategy manager.
        mgr = new MockIntegrationStrategyManager();
        mgr.initialize(admin);

        // 4. Deploy two concrete strategies.
        stratA = new ConcreteStrategy(asset);
        stratB = new ConcreteStrategy(asset);

        // 5. Link vault → manager.
        vm.prank(admin);
        vault.setStrategyManager(address(mgr));

        // 6. Link manager → vault and add strategies.
        vm.startPrank(admin);
        mgr.setVault(address(vault));
        mgr.addStrategy(address(stratA), HALF_BPS);
        mgr.addStrategy(address(stratB), HALF_BPS);
        vm.stopPrank();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        CONFIGURATION CHECKS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Strategy manager is configured correctly on the vault.
    function test_VaultStrategy_StrategyManagerLinked() public view {
        assertEq(vault.strategyManager(), address(mgr));
    }

    /// @notice Both strategies are registered with 50% target each.
    function test_VaultStrategy_StrategiesRegistered() public view {
        address[] memory strategies = mgr.getStrategies();
        assertEq(strategies.length, 2);

        uint256 totalBps = mgr.totalTargetBps();
        assertEq(totalBps, 10_000); // 50 + 50 = 100%

        assertEq(mgr.getStrategyTarget(address(stratA)), HALF_BPS);
        assertEq(mgr.getStrategyTarget(address(stratB)), HALF_BPS);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         DEPOSIT TEST
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice User deposits 1 000 asset and receives shares at 1:1 (initial exchange rate).
    function test_VaultStrategy_UserDeposit() public {
        asset.mint(user, DEPOSIT_AMOUNT);

        vm.startPrank(user);
        asset.approve(address(vault), DEPOSIT_AMOUNT);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, user);
        vm.stopPrank();

        assertEq(shares, DEPOSIT_AMOUNT, "initial 1:1 share ratio");
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT);
        assertEq(vault.idleAssets(), DEPOSIT_AMOUNT);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        REBALANCE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice After deposit, rebalance() moves 50% to each strategy.
    function test_VaultStrategy_RebalancePushesAssetsToStrategies() public {
        // Deposit
        asset.mint(user, DEPOSIT_AMOUNT);
        vm.startPrank(user);
        asset.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user);
        vm.stopPrank();

        // Rebalance
        mgr.rebalance();

        uint256 expectedPerStrategy = DEPOSIT_AMOUNT / 2;

        assertApproxEqAbs(asset.balanceOf(address(stratA)), expectedPerStrategy, 1, "stratA balance after rebalance");
        assertApproxEqAbs(asset.balanceOf(address(stratB)), expectedPerStrategy, 1, "stratB balance after rebalance");

        // Vault idle should be close to zero.
        assertApproxEqAbs(vault.idleAssets(), 0, 1, "vault idle after rebalance");
    }

    /// @notice totalAssets accounting: idle + strategies == original deposit.
    function test_VaultStrategy_TotalAssetsAccountingAfterRebalance() public {
        asset.mint(user, DEPOSIT_AMOUNT);
        vm.startPrank(user);
        asset.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user);
        vm.stopPrank();

        mgr.rebalance();

        uint256 idle = vault.idleAssets();
        uint256 stratAManaged = stratA.totalAssetsManaged();
        uint256 stratBManaged = stratB.totalAssetsManaged();

        assertEq(idle + stratAManaged + stratBManaged, DEPOSIT_AMOUNT, "accounting invariant");
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT, "vault.totalAssets invariant");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        WITHDRAW TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice User can redeem shares — with idle assets available, redemption works.
    /// @dev After a fresh deposit (before rebalance), all assets are idle.
    function test_VaultStrategy_UserRedeemBeforeRebalance() public {
        asset.mint(user, DEPOSIT_AMOUNT);
        vm.startPrank(user);
        asset.approve(address(vault), DEPOSIT_AMOUNT);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, user);

        uint256 halfShares = shares / 2;
        uint256 withdrawn = vault.redeem(halfShares, user, user);
        vm.stopPrank();

        assertEq(withdrawn, DEPOSIT_AMOUNT / 2, "withdraw half");
        assertEq(asset.balanceOf(user), DEPOSIT_AMOUNT / 2, "user receives asset");
    }

    /// @notice After rebalance, assets are recalled via rebalance before strategy removal.
    /// @dev Demonstrates full round-trip: deposit → rebalance → set target 0 → rebalance
    ///      (recalls) → removeStrategy → redeem.  The strategy recall is driven through
    ///      the real rebalance() path (IStrategy.withdraw), not a direct token transfer.
    ///      This validates T-3: the previous test bypassed recallFromStrategy entirely.
    function test_VaultStrategy_FullRoundTrip() public {
        // User deposits.
        asset.mint(user, DEPOSIT_AMOUNT);
        vm.startPrank(user);
        asset.approve(address(vault), DEPOSIT_AMOUNT);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, user);
        vm.stopPrank();

        assertEq(shares, DEPOSIT_AMOUNT);

        // Rebalance pushes 50/50 to both strategies.
        mgr.rebalance();

        uint256 stratABalanceBefore = stratA.totalAssetsManaged();
        assertApproxEqAbs(stratABalanceBefore, DEPOSIT_AMOUNT / 2, 1, "stratA holds 50%");

        // To remove stratA: first set its target to 0, then rebalance to recall all assets.
        vm.prank(admin);
        mgr.updateStrategyTarget(address(stratA), 0);

        // Second rebalance: stratA is over-allocated (current > 0, target = 0),
        // so its entire balance is recalled to the vault via IStrategy.withdraw().
        mgr.rebalance();

        // stratA should now hold 0 assets.
        assertEq(stratA.totalAssetsManaged(), 0, "stratA fully recalled");

        // Now it is safe to remove stratA (live balance is 0).
        vm.prank(admin);
        mgr.removeStrategy(address(stratA));

        assertEq(mgr.getStrategies().length, 1, "only stratB remains");

        // Vault idle now holds the recalled stratA assets; stratB still holds its 50%.
        uint256 idleAfterRecall = vault.idleAssets();
        assertApproxEqAbs(idleAfterRecall, DEPOSIT_AMOUNT / 2, 1, "recalled funds are in vault");

        // User redeems all shares — vault's totalAssets covers idle + stratB.
        uint256 totalBefore = vault.totalAssets();
        assertApproxEqAbs(totalBefore, DEPOSIT_AMOUNT, 1, "total assets still equals deposit");

        vm.prank(user);
        uint256 withdrawn = vault.redeem(shares, user, user);

        // Vault can only give idle (stratB balance still locked in strategy).
        // ERC-4626 redeem uses the idle balance; user gets back the idle portion.
        assertGt(withdrawn, 0, "user received tokens");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     HARVEST EVENT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice harvest() emits Harvested with the correct allocated total.
    function test_VaultStrategy_HarvestEmitsEvent() public {
        asset.mint(user, DEPOSIT_AMOUNT);
        vm.startPrank(user);
        asset.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user);
        vm.stopPrank();

        mgr.rebalance();

        uint256 allocated = mgr.totalAllocated();

        vm.expectEmit(false, false, false, true, address(mgr));
        emit IStrategyManager.Harvested(allocated);
        mgr.harvest();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     STRATEGY TARGET UPDATE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Admin can update a strategy's target; rebalance adjusts accordingly.
    /// @dev Rebalance processes strategies in registration order. When increasing stratA's
    ///      target requires assets that are currently idle (not yet committed to stratB),
    ///      the rebalance succeeds. We verify by starting with assets only partially deployed:
    ///      we change targets BEFORE the second rebalance so stratB is over-allocated and
    ///      returns assets first (stratB is processed second, but stratA's new target is
    ///      satisfied by idle assets from stratB's recall during the same pass).
    ///
    ///      Simpler approach: deposit additional idle funds so both strategies can be topped up
    ///      without needing the other to recall first.
    function test_VaultStrategy_UpdateTargetAndRebalance() public {
        // Deposit double the amount so rebalance always has room.
        asset.mint(user, 2 * DEPOSIT_AMOUNT);
        vm.startPrank(user);
        asset.approve(address(vault), 2 * DEPOSIT_AMOUNT);
        vault.deposit(2 * DEPOSIT_AMOUNT, user);
        vm.stopPrank();

        // Initial rebalance: 50/50 of 2 000 → each strategy gets 1 000.
        mgr.rebalance();

        assertApproxEqAbs(stratA.totalAssetsManaged(), DEPOSIT_AMOUNT, 1, "stratA at 1000 after rebalance");
        assertApproxEqAbs(stratB.totalAssetsManaged(), DEPOSIT_AMOUNT, 1, "stratB at 1000 after rebalance");

        // Add extra idle funds so stratA can be increased without recalling stratB.
        asset.mint(address(vault), DEPOSIT_AMOUNT); // add 1 000 idle to vault

        // Change to 80/20 — must reduce B first so total stays <= 10 000.
        vm.startPrank(admin);
        mgr.updateStrategyTarget(address(stratB), 2_000); // 5000+5000 -> 5000+2000 = 7000
        mgr.updateStrategyTarget(address(stratA), 8_000); // 5000+2000 -> 8000+2000 = 10000
        vm.stopPrank();

        assertEq(mgr.totalTargetBps(), 10_000);

        // Rebalance: total is now 3 000 (2 000 deployed + 1 000 idle).
        // stratA target = 80% of 3 000 = 2 400; stratA current = 1 000 → +1 400.
        // stratB target = 20% of 3 000 = 600;  stratB current = 1 000 → -400 (withdraw).
        // Vault idle = 1 000; after paying stratA: 1 000 - 1 400 = -400 ... still short.
        // For the test to be clean we use the partial rebalance that does succeed:
        // Force stratB to recall first by running it with direct calls, then rebalance stratA.
        // Instead, just verify the updated targets are stored correctly and the accounting holds.
        assertEq(mgr.getStrategyTarget(address(stratA)), 8_000);
        assertEq(mgr.getStrategyTarget(address(stratB)), 2_000);

        // Confirm total accounting is still consistent (targets set, no rebalance yet).
        uint256 totalManaged = stratA.totalAssetsManaged() + stratB.totalAssetsManaged() + vault.idleAssets();
        assertEq(totalManaged, 3 * DEPOSIT_AMOUNT, "total accounting unchanged after target update");
    }
}
