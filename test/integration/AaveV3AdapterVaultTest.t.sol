// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title AaveV3AdapterVaultTest
/// @notice End-to-end integration test wiring the committed `AaveV3Adapter` (the Aave v3 supply
///         adapter facet) through Lattice's unchanged `VaultCore` + `StrategyManager` spine,
///         proving the adapter "becomes a strategy" with zero changes to the spine.
///
/// Flow proven:
///  1. The Aave adapter is registered in StrategyManager as the IStrategy with a target bps.
///  2. `vault.deposit` then `mgr.rebalance()` PUSHES idle vault funds to the adapter via a bare
///     ERC-20 transfer (no deposit callback) — funds land in the adapter's idle balance, not yet
///     supplied to Aave (so `totalAssetsManaged()` reads 0).
///  3. The keeper/test calls `adapter.deploy()` explicitly to sweep idle into the mock Aave Pool
///     (idle -> aTokens). This is the chosen trigger: VaultCore's bare-transfer push has no
///     callback, so the sweep must be a separate, explicit call.
///  4. Accounting invariant: `vault.totalAssets()` == deposit across rebalance + deploy, where the
///     adapter contributes `totalAssetsManaged()` (the mock aToken balance) to `totalAllocated()`.
///  5. A recall round-trips honestly: dropping the target to 0 and rebalancing makes the manager
///     call `IStrategy.withdraw`, pulling funds from the mock pool back to the vault.

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AaveV3Adapter} from "@lattice/defi/AaveV3Adapter.sol";
import {StrategyManager} from "@lattice/defi/StrategyManager.sol";
import {VaultCore} from "@lattice/defi/VaultCore.sol";
import {AaveV3AdapterLib} from "@lattice/defi/libraries/AaveV3AdapterLib.sol";
import {StrategyManagerLib} from "@lattice/defi/libraries/StrategyManagerLib.sol";
import {VaultCoreLib} from "@lattice/defi/libraries/VaultCoreLib.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {ERC20Lib} from "@lattice/tokens/libraries/ERC20Lib.sol";
import {ERC4626Lib} from "@lattice/tokens/libraries/ERC4626Lib.sol";
import {Test} from "forge-std/Test.sol";

// Reuse the mocks from the supply test by importing them.
import {MockAToken, MockAaveAdapter, MockAaveV3Pool, MockAsset} from "./AaveV3AdapterSupplyTest.t.sol";

//*//////////////////////////////////////////////////////////////////////////
//                         MOCK VAULT (ERC4626 + VaultCore)
//////////////////////////////////////////////////////////////////////////*//

contract MockVault is VaultCore {
    function initialize(address asset_, address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        ERC20Lib.__ERC20_init("Vault Share", "vSHARE");
        ERC4626Lib.__ERC4626_init(asset_, 0);
        VaultCoreLib.__VaultCore_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) external view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                          MOCK STRATEGY MANAGER
//////////////////////////////////////////////////////////////////////////*//

contract MockManager is StrategyManager {
    function initialize(address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        StrategyManagerLib.__StrategyManager_init();
        InitializableLib.postInitializer(s);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                              TEST SUITE
//////////////////////////////////////////////////////////////////////////*//

contract AaveV3AdapterVaultTest is Test {
    MockAsset asset;
    MockAToken aToken;
    MockAaveV3Pool pool;
    MockAaveAdapter adapter;
    MockVault vault;
    MockManager mgr;

    address admin = address(0xAD);
    address user = address(0xA1);
    address treasury = address(0x7E0);
    bytes32 constant FEED_KEY = keccak256("USDC/USD");
    uint256 constant DEPOSIT = 1_000e6;

    function setUp() public {
        asset = new MockAsset();
        aToken = new MockAToken(asset);
        pool = new MockAaveV3Pool();
        pool.setAToken(asset, aToken);

        vault = new MockVault();
        vault.initialize(address(asset), admin);

        mgr = new MockManager();
        mgr.initialize(admin);

        adapter = new MockAaveAdapter();
        adapter.initialize(admin, address(pool), address(asset), address(vault), treasury, FEED_KEY, 1.05e18);

        vm.startPrank(admin);
        vault.setStrategyManager(address(mgr));
        mgr.setVault(address(vault));
        mgr.addStrategy(address(adapter), 10_000); // 100% target
        // The StrategyManager is the adapter's authorized operator: it is the only caller permitted
        // to invoke deploy/withdraw/harvest. The rebalance() recall path runs as `mgr`, and the
        // explicit deploy() sweeps below are pranked as `mgr` to mirror the keeper-relayed call.
        adapter.setOperator(address(mgr));
        vm.stopPrank();
    }

    /// @notice Deposit -> rebalance pushes the bare transfer to the adapter -> deploy() sweeps
    ///         idle into the mock Aave Pool, with `vault.totalAssets()` conserved across the route.
    function test_RebalanceThenDeploy_RoutesFundsIntoAave() public {
        // User deposits.
        asset.mint(user, DEPOSIT);
        vm.startPrank(user);
        asset.approve(address(vault), DEPOSIT);
        vault.deposit(DEPOSIT, user);
        vm.stopPrank();

        assertEq(vault.idleAssets(), DEPOSIT, "all idle pre-rebalance");

        // Rebalance pushes the bare transfer to the adapter (adapter now holds idle asset).
        mgr.rebalance();
        assertEq(asset.balanceOf(address(adapter)), DEPOSIT, "pushed to adapter, not yet supplied");
        // Before deploy(), the funds sit idle in the adapter (not yet supplied to Aave). The
        // adapter's `totalAssetsManaged()` MUST still count that idle balance so NAV does not drop
        // in the allocate→(no deploy) window — the supplied aToken leg is 0, the idle leg is DEPOSIT.
        assertEq(adapter.totalAssetsManaged(), DEPOSIT, "idle counted before deploy() (no NAV gap)");

        // Keeper sweeps idle into Aave (the StrategyManager is the authorized operator).
        vm.prank(address(mgr));
        uint256 deployed = adapter.deploy();
        assertEq(deployed, DEPOSIT, "swept all");
        assertEq(adapter.totalAssetsManaged(), DEPOSIT, "now supplied 1:1");
        assertEq(asset.balanceOf(address(adapter)), 0, "adapter idle drained");

        // Vault accounting: idle (0) + allocated (adapter.totalAssetsManaged) == deposit.
        assertEq(vault.totalAssets(), DEPOSIT, "share price intact across the route");
    }

    /// @notice NAV-stability invariant (the HIGH fix). `allocateToStrategy` moves idle vault assets
    ///         into the adapter via a bare ERC-20 transfer that does NOT call `deploy()`. Because the
    ///         adapter's `totalAssetsManaged()` includes its own idle underlying balance, the vault's
    ///         share price (`totalAssets()`) is UNCHANGED across BOTH the allocate (no deploy) step
    ///         AND the subsequent deploy() — proving allocated-but-undeployed funds never leave NAV
    ///         (no theft window) and that adding idle does not double-count (invariant across deploy).
    function test_NavStableAcrossAllocateAndDeploy() public {
        asset.mint(user, DEPOSIT);
        vm.startPrank(user);
        asset.approve(address(vault), DEPOSIT);
        vault.deposit(DEPOSIT, user);
        vm.stopPrank();

        uint256 navBefore = vault.totalAssets();
        assertEq(navBefore, DEPOSIT, "NAV == deposit at rest (all idle in vault)");

        // Allocate: vault idle -> adapter idle (bare transfer, NO deploy). Pre-fix the adapter
        // reported 0 here and NAV cratered to 0 (the attacker's cheap-share window). Post-fix the
        // adapter counts its idle, so NAV is invariant.
        mgr.rebalance();
        assertEq(asset.balanceOf(address(adapter)), DEPOSIT, "funds now idle in adapter, not deployed");
        assertEq(vault.totalAssets(), navBefore, "NAV UNCHANGED across allocate (no deploy)");

        // Deploy: adapter idle -> Aave aToken position. idle drops to ~0, the position grows by the
        // same amount, so the sum (and NAV) is invariant — proving no double-count.
        vm.prank(address(mgr));
        adapter.deploy();
        assertEq(asset.balanceOf(address(adapter)), 0, "adapter idle now deployed");
        assertEq(vault.totalAssets(), navBefore, "NAV STILL UNCHANGED across deploy (no double-count)");
    }

    /// @notice Dropping the target to 0 and rebalancing recalls funds from the mock Aave Pool back
    ///         into the vault via `IStrategy.withdraw`, with accounting conserved end-to-end.
    function test_RecallViaRebalance_PullsFromAaveBackToVault() public {
        asset.mint(user, DEPOSIT);
        vm.startPrank(user);
        asset.approve(address(vault), DEPOSIT);
        vault.deposit(DEPOSIT, user);
        vm.stopPrank();

        mgr.rebalance();
        vm.prank(address(mgr));
        adapter.deploy();
        assertEq(adapter.totalAssetsManaged(), DEPOSIT);

        // Drop target to 0, rebalance: manager calls IStrategy.withdraw to pull funds back.
        vm.prank(admin);
        mgr.updateStrategyTarget(address(adapter), 0);
        mgr.rebalance();

        assertEq(adapter.totalAssetsManaged(), 0, "fully recalled from Aave");
        assertEq(vault.idleAssets(), DEPOSIT, "funds back in vault");
        assertEq(vault.totalAssets(), DEPOSIT, "accounting conserved");
    }
}
