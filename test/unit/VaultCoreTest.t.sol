// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {VaultCore} from "@lattice/defi/VaultCore.sol";
import {VaultCoreLib} from "@lattice/defi/libraries/VaultCoreLib.sol";
import {IVaultCore} from "@lattice/interfaces/defi/IVaultCore.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC4626Lib} from "@lattice/tokens/ERC4626/libraries/ERC4626Lib.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                          MOCK UNDERLYING ERC20
//////////////////////////////////////////////////////////////////////////*//

/// @notice Simple mintable ERC-20 used as the vault's underlying asset.
contract MockERC20 {
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
//                           MOCK VAULT CONTRACT
//////////////////////////////////////////////////////////////////////////*//

/// @notice VaultCore mock that also exposes VaultCoreLib's init.
contract MockVaultCoreContract is VaultCore {
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
}

//*//////////////////////////////////////////////////////////////////////////
//                                 TESTS
//////////////////////////////////////////////////////////////////////////*//

/// @title VaultCoreTest
/// @notice Tests for the VaultCore three-layer module.
contract VaultCoreTest is Test {
    MockVaultCoreContract vault;
    MockERC20 underlying;
    MockStrategyManager stratManager;

    address admin = address(0xAD);
    address user = address(0xA1);
    address manager = address(0); // set to stratManager after deploy

    function setUp() public {
        underlying = new MockERC20();
        vault = new MockVaultCoreContract();
        stratManager = new MockStrategyManager();
        manager = address(stratManager);

        vm.prank(admin);
        vault.initialize(address(underlying), admin);
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
        underlying.mint(address(vault), 1000e18);
        assertEq(vault.totalAssets(), 1000e18);
        assertEq(vault.idleAssets(), 1000e18);
    }

    /// @notice With a manager, totalAssets = idle + manager.totalAllocated().
    function test_TotalAssets_WithManager_IncludesAllocated() public {
        vm.prank(admin);
        vault.setStrategyManager(manager);

        underlying.mint(address(vault), 600e18);
        stratManager.setTotalAllocated(400e18);

        assertEq(vault.idleAssets(), 600e18);
        assertEq(vault.totalAssets(), 1000e18);
        assertEq(vault.allocatedAssets(), 400e18);
    }

    /// @notice allocatedAssets returns 0 when no manager is set.
    function test_AllocatedAssets_NoManager_IsZero() public {
        underlying.mint(address(vault), 500e18);
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
        underlying.mint(address(vault), 500e18);

        vm.prank(manager);
        vault.allocateToStrategy(strategy, 200e18);

        // Assets moved from vault to strategy
        assertEq(underlying.balanceOf(address(vault)), 300e18);
        assertEq(underlying.balanceOf(strategy), 200e18);
    }

    /// @notice allocateToStrategy emits AssetsAllocated event.
    function test_AllocateToStrategy_EmitsEvent() public {
        vm.prank(admin);
        vault.setStrategyManager(manager);

        address strategy = address(0x5678);
        underlying.mint(address(vault), 500e18);

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
        underlying.mint(address(vault), 500e18);

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
        underlying.approve(address(vault), 1000e18);
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
        assertTrue(vault.supportsInterface(id), "should support IVaultCore");
    }

    /// @notice VaultCore still supports IERC4626 interface.
    function test_SupportsInterface_IERC4626() public view {
        bytes4 id = type(IERC4626).interfaceId;
        assertTrue(vault.supportsInterface(id), "should support IERC4626");
    }
}
