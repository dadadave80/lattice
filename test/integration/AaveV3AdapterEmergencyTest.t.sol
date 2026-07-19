// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {AaveV3Adapter} from "@lattice/defi/AaveV3Adapter.sol";
import {AaveV3AdapterLib} from "@lattice/defi/libraries/AaveV3AdapterLib.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {EMERGENCY_GUARDIAN_ROLE, EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {Test} from "forge-std/Test.sol";

import {MockAToken, MockAaveV3Pool, MockAsset} from "./AaveV3AdapterSupplyTest.t.sol";

/// @notice Adapter composed with Pausable + EmergencyStop facets (as a real Diamond would).
contract MockGuardedAdapter is AaveV3Adapter, Pausable, EmergencyStop {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(Pausable, EmergencyStop) returns (bytes memory) {}

    function initialize(
        address admin_,
        address provider_,
        address asset_,
        address vault_,
        address rewardRecipient_,
        bytes32 feedKey_,
        uint256 minHf_
    ) external {
        bytes32 s = InitializableLib.initializableSlot();
        s = InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        ReentrancyGuardLib.__ReentrancyGuard_init();
        PausableLib.__Pausable_init();
        EmergencyStopLib.__EmergencyStop_init();
        AaveV3AdapterLib.__AaveV3Adapter_init(provider_, asset_, vault_, rewardRecipient_, feedKey_, minHf_);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) external view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

contract AaveV3AdapterEmergencyTest is Test {
    MockAsset asset;
    MockAToken aToken;
    MockAaveV3Pool pool;
    MockGuardedAdapter adapter;
    address admin = address(0xAD);
    address guardian = address(0x6);
    address vault = address(0x7A17);
    address treasury = address(0x7E0);
    bytes32 constant FEED_KEY = keccak256("USDC/USD");

    function setUp() public {
        asset = new MockAsset();
        aToken = new MockAToken(asset);
        pool = new MockAaveV3Pool();
        pool.setAToken(asset, aToken);
        asset.mint(address(pool), 1_000_000e6);

        adapter = new MockGuardedAdapter();
        adapter.initialize(admin, address(pool), address(asset), vault, treasury, FEED_KEY, 1.05e18);
        vm.prank(admin);
        adapter.addGuardian(guardian);
        // Authorize this test contract as the operator so the direct deploy/withdraw/harvest calls
        // (which the StrategyManager would make in production) pass the operator gate.
        vm.prank(admin);
        adapter.setOperator(address(this));

        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
    }

    function test_Pause_BlocksDeploy() public {
        vm.prank(admin);
        adapter.pause();
        asset.mint(address(adapter), 100e6);
        vm.expectRevert(IProtocolAdapter.ProtocolAdapterPaused.selector);
        adapter.deploy();
    }

    function test_EmergencyStop_BlocksDeploy() public {
        vm.prank(guardian);
        adapter.emergencyStop("incident");
        asset.mint(address(adapter), 100e6);
        vm.expectRevert(IProtocolAdapter.ProtocolAdapterPaused.selector);
        adapter.deploy();
    }

    function test_IsPaused_ReflectsBothControls() public {
        assertFalse(adapter.isPaused());
        vm.prank(admin);
        adapter.pause();
        assertTrue(adapter.isPaused(), "paused => isPaused");
        vm.prank(admin);
        adapter.unpause();
        vm.prank(guardian);
        adapter.emergencyStop("x");
        assertTrue(adapter.isPaused(), "stopped => isPaused");
    }

    function test_EmergencyWithdraw_FullyExitsToVault_EvenWhenStopped() public {
        // Stop the adapter, then emergency-withdraw must still fully exit.
        vm.prank(guardian);
        adapter.emergencyStop("incident");

        vm.prank(admin);
        uint256 recovered = adapter.emergencyWithdraw();
        assertEq(recovered, 1_000e6, "all collateral recovered");
        assertEq(asset.balanceOf(vault), 1_000e6, "funds returned to vault");
        assertEq(adapter.totalAssetsManaged(), 0, "position closed");
    }

    function test_EmergencyWithdraw_OnlyAdmin() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(); // AccessControlUnauthorizedAccount
        adapter.emergencyWithdraw();
    }
}
