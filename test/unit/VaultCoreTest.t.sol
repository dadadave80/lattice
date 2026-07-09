// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {VaultCoreTestBase} from "@lattice-test/base/VaultCoreTestBase.sol";
import {DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IVaultCore} from "@lattice/interfaces/defi/IVaultCore.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";

//*//////////////////////////////////////////////////////////////////////////
//                         MOCK STRATEGY MANAGER
//////////////////////////////////////////////////////////////////////////*//

/// @notice Records calls and returns a configurable `totalAllocated` amount.
contract MockStrategyManager {
    uint256 public totalAllocatedAmount;

    function setTotalAllocated(uint256 amount) external {
        totalAllocatedAmount = amount;
    }

    function totalAllocated() external view returns (uint256) {
        return totalAllocatedAmount;
    }
}

/// @notice Strategy manager whose totalAllocated() always reverts (simulates bricked strategy).
/// @dev Used for T-1: VaultCore.totalAssets() must fall back to idle when manager reverts.
contract RevertingStrategyManager {
    function totalAllocated() external pure returns (uint256) {
        revert("manager bricked");
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                 TESTS
//////////////////////////////////////////////////////////////////////////*//

/// @title VaultCoreTest
/// @notice Tests for the VaultCore three-layer module, exercised through a REAL {Diamond} assembled by the
///         ready-to-deploy {DeployVaultCore} script (see {VaultCoreTestBase}). The underlying asset is itself a
///         real base ERC-20 diamond; every vault/strategy call routes through the diamond's `delegatecall`
///         dispatch, not a flattened inheritance mock. `supportsInterface` comes from the cut-in `ERC165Facet`;
///         `DEFAULT_ADMIN_ROLE` is granted to `admin` at init (see {VaultCoreInit}).
contract VaultCoreTest is VaultCoreTestBase {
    MockStrategyManager stratManager;

    address user = address(0xA1);
    address manager = address(0); // set to stratManager after deploy

    function setUp() public override {
        super.setUp(); // deploys the underlying ERC-20 diamond + the VaultCore diamond, wires handles, admin=0xAD

        stratManager = new MockStrategyManager();
        manager = address(stratManager);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       SET STRATEGY MANAGER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Admin can set a valid strategy manager.
    function test_SetStrategyManager_Admin() public {
        vm.prank(admin);
        vault.setStrategyManager(manager);
        assertEq(vault.strategyManager(), manager);
    }

    /// @notice Non-admin cannot set strategy manager.
    function test_SetStrategyManager_NonAdmin_Reverts() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, DEFAULT_ADMIN_ROLE
            )
        );
        vault.setStrategyManager(manager);
    }

    /// @notice Setting address(0) as manager reverts with VaultCoreInvalidManager.
    function test_SetStrategyManager_ZeroAddress_Reverts() public {
        vm.prank(admin);
        vm.expectRevert(IVaultCore.VaultCoreInvalidManager.selector);
        vault.setStrategyManager(address(0));
    }

    /// @notice Setting manager emits StrategyManagerSet event.
    function test_SetStrategyManager_EmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit IVaultCore.StrategyManagerSet(manager);
        vault.setStrategyManager(manager);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          TOTAL ASSETS TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Without a manager, totalAssets equals idle balance.
    function test_TotalAssets_NoManager_EqualsIdle() public {
        underlying.mint(vaultAddr, 1000e18);
        assertEq(vault.totalAssets(), 1000e18);
        assertEq(vault.idleAssets(), 1000e18);
    }

    /// @notice With a manager, totalAssets = idle + manager.totalAllocated().
    function test_TotalAssets_WithManager_IncludesAllocated() public {
        vm.prank(admin);
        vault.setStrategyManager(manager);

        underlying.mint(vaultAddr, 600e18);
        stratManager.setTotalAllocated(400e18);

        assertEq(vault.idleAssets(), 600e18);
        assertEq(vault.totalAssets(), 1000e18);
        assertEq(vault.allocatedAssets(), 400e18);
    }

    /// @notice allocatedAssets returns 0 when no manager is set.
    function test_AllocatedAssets_NoManager_IsZero() public {
        underlying.mint(vaultAddr, 500e18);
        assertEq(vault.allocatedAssets(), 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      ALLOCATE TO STRATEGY TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Non-manager calling allocateToStrategy reverts.
    function test_AllocateToStrategy_NonManager_Reverts() public {
        vm.prank(admin);
        vault.setStrategyManager(manager);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IVaultCore.VaultCoreUnauthorizedManager.selector, user));
        vault.allocateToStrategy(address(0x1234), 100e18);
    }

    /// @notice Manager can allocate idle assets to a strategy.
    function test_AllocateToStrategy_Manager_TransfersAssets() public {
        vm.prank(admin);
        vault.setStrategyManager(manager);

        address strategy = address(0x5678);
        underlying.mint(vaultAddr, 500e18);

        vm.prank(manager);
        vault.allocateToStrategy(strategy, 200e18);

        // Assets moved from vault to strategy
        assertEq(underlying.balanceOf(vaultAddr), 300e18);
        assertEq(underlying.balanceOf(strategy), 200e18);
    }

    /// @notice allocateToStrategy emits AssetsAllocated event.
    function test_AllocateToStrategy_EmitsEvent() public {
        vm.prank(admin);
        vault.setStrategyManager(manager);

        address strategy = address(0x5678);
        underlying.mint(vaultAddr, 500e18);

        vm.prank(manager);
        vm.expectEmit(true, false, false, true);
        emit IVaultCore.AssetsAllocated(strategy, 200e18);
        vault.allocateToStrategy(strategy, 200e18);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      RECALL FROM STRATEGY TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Non-manager calling recallFromStrategy reverts.
    function test_RecallFromStrategy_NonManager_Reverts() public {
        vm.prank(admin);
        vault.setStrategyManager(manager);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IVaultCore.VaultCoreUnauthorizedManager.selector, user));
        vault.recallFromStrategy(address(0x1234), 100e18);
    }

    /// @notice Manager can emit recall (strategy handles the actual transfer back).
    function test_RecallFromStrategy_Manager_EmitsEvent() public {
        vm.prank(admin);
        vault.setStrategyManager(manager);

        address strategy = address(0x5678);

        vm.prank(manager);
        vm.expectEmit(true, false, false, true);
        emit IVaultCore.AssetsRecalled(strategy, 100e18);
        vault.recallFromStrategy(strategy, 100e18);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    T-1: REVERTING MANAGER DoS RESILIENCE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice When the strategy manager's totalAllocated() reverts, vault falls back to idle (T-1).
    /// @dev VaultCoreLib.totalAssets() wraps the staticcall in (bool ok, bytes data) and returns
    ///      idle-only when the call fails. This ensures a bricked strategy/manager cannot DoS
    ///      the vault's ERC-4626 operations.
    function test_TotalAssets_RevertingManager_FallsBackToIdle() public {
        RevertingStrategyManager badManager = new RevertingStrategyManager();
        vm.prank(admin);
        vault.setStrategyManager(address(badManager));

        // Mint idle assets to vault.
        underlying.mint(vaultAddr, 500e18);

        // totalAssets() must not revert; it should return idle only.
        uint256 total = vault.totalAssets();
        assertEq(total, 500e18, "totalAssets must equal idle when manager reverts");
        assertEq(vault.idleAssets(), 500e18, "idleAssets unaffected");
    }

    /// @notice Share price reflects idle-only total when manager is bricked (T-1).
    function test_SharePrice_RevertingManager_UseIdleOnly() public {
        RevertingStrategyManager badManager = new RevertingStrategyManager();

        // Deposit before setting bricked manager so shares exist.
        underlying.mint(user, 1000e18);
        vm.startPrank(user);
        underlying.approve(vaultAddr, 1000e18);
        vault.deposit(1000e18, user);
        vm.stopPrank();

        // Install bricked manager.
        vm.prank(admin);
        vault.setStrategyManager(address(badManager));

        // totalAssets falls back to idle = 1000.
        assertEq(vault.totalAssets(), 1000e18, "totalAssets falls back to idle");

        // previewRedeem reflects the idle-only share price correctly.
        uint256 shares = vault.balanceOf(user);
        uint256 preview = vault.previewRedeem(shares);
        assertApproxEqAbs(preview, 1000e18, 1, "previewRedeem uses idle-only total");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice VaultCore registers IVaultCore interface ID.
    function test_SupportsInterface_IVaultCore() public view {
        bytes4 id = type(IVaultCore).interfaceId;
        assertTrue(ERC165Facet(vaultAddr).supportsInterface(id), "should support IVaultCore");
    }

    /// @notice VaultCore still supports IERC4626 interface.
    function test_SupportsInterface_IERC4626() public view {
        bytes4 id = type(IERC4626).interfaceId;
        assertTrue(ERC165Facet(vaultAddr).supportsInterface(id), "should support IERC4626");
    }
}
