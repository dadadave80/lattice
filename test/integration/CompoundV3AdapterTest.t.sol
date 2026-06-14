// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {CompoundV3Adapter} from "@lattice/defi/CompoundV3Adapter.sol";
import {StrategyManager} from "@lattice/defi/StrategyManager.sol";
import {VaultCore} from "@lattice/defi/VaultCore.sol";
import {CompoundV3AdapterLib} from "@lattice/defi/libraries/CompoundV3AdapterLib.sol";
import {StrategyManagerLib} from "@lattice/defi/libraries/StrategyManagerLib.sol";
import {VaultCoreLib} from "@lattice/defi/libraries/VaultCoreLib.sol";
import {IProtocolAdapter} from "@lattice/interfaces/IProtocolAdapter.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {ERC20Lib} from "@lattice/tokens/libraries/ERC20Lib.sol";
import {ERC4626Lib} from "@lattice/tokens/libraries/ERC4626Lib.sol";
import {Test} from "forge-std/Test.sol";

import {MockAsset} from "./AaveV3AdapterSupplyTest.t.sol";

//*//////////////////////////////////////////////////////////////////////////
//                         MOCK COMET + REWARDS
//////////////////////////////////////////////////////////////////////////*//

contract MockComet {
    MockAsset public base;
    mapping(address => uint256) public balanceOf;

    constructor(MockAsset b) {
        base = b;
    }

    function baseToken() external view returns (address) {
        return address(base);
    }

    function accrueAccount(address) external {}

    function supply(address, uint256 amount) external {
        require(base.transferFrom(msg.sender, address(this), amount), "pull");
        balanceOf[msg.sender] += amount;
    }

    function withdraw(address, uint256 amount) external {
        uint256 bal = balanceOf[msg.sender];
        uint256 amt = amount > bal ? bal : amount;
        balanceOf[msg.sender] -= amt;
        require(base.transfer(msg.sender, amt), "send");
    }

    /// @dev simulate yield accrual by minting balance.
    function accrueYield(address who, uint256 amt) external {
        balanceOf[who] += amt;
        base.mint(address(this), amt);
    }
}

contract MockComp {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 a) external {
        balanceOf[to] += a;
    }

    function transfer(address to, uint256 a) external returns (bool) {
        require(balanceOf[msg.sender] >= a, "bal");
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
        return true;
    }
}

contract MockCometRewards {
    MockComp public comp;
    uint256 public claimable;

    constructor(MockComp c) {
        comp = c;
    }

    function setClaimable(uint256 a) external {
        claimable = a;
    }

    function rewardConfig(address) external view returns (address, uint64, bool) {
        return (address(comp), 1, true);
    }

    function claimTo(address, address, address to, bool) external {
        if (claimable > 0) comp.mint(to, claimable);
        claimable = 0;
    }
}

contract MockCompoundAdapter is CompoundV3Adapter {
    function initialize(address admin_, address comet_, address asset_, address vault_, address recipient_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        ReentrancyGuardLib.__ReentrancyGuard_init();
        CompoundV3AdapterLib.__CompoundV3Adapter_init(comet_, asset_, vault_, recipient_);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) external view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

contract CompoundV3AdapterTest is Test {
    MockAsset asset;
    MockComet comet;
    MockCompoundAdapter adapter;
    MockComp comp;
    MockCometRewards rewards;
    address admin = address(0xAD);
    address vault = address(0x7A17);
    address treasury = address(0x7E0);

    function setUp() public {
        asset = new MockAsset();
        comet = new MockComet(asset);
        comp = new MockComp();
        rewards = new MockCometRewards(comp);
        adapter = new MockCompoundAdapter();
        adapter.initialize(admin, address(comet), address(asset), vault, treasury);
        vm.startPrank(admin);
        adapter.setCometRewards(address(rewards));
        // Authorize this test contract as the operator so the direct deploy/withdraw/harvest calls
        // below (which the StrategyManager would make in production) pass the operator gate.
        adapter.setOperator(address(this));
        vm.stopPrank();
    }

    function test_Deploy_SuppliesToComet() public {
        asset.mint(address(adapter), 1_000e6);
        uint256 deployed = adapter.deploy();
        assertEq(deployed, 1_000e6);
        assertEq(adapter.totalAssetsManaged(), 1_000e6, "1:1 base accounting");
    }

    function test_TotalAssets_ReflectsAccruedYield() public {
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        comet.accrueYield(address(adapter), 50e6); // interest accrues
        assertEq(adapter.totalAssetsManaged(), 1_050e6, "yield included via balanceOf");
    }

    function test_Withdraw_ReturnsRealAmount() public {
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        uint256 got = adapter.withdraw(400e6, vault);
        assertEq(got, 400e6);
        assertEq(asset.balanceOf(vault), 400e6);
    }

    function test_Withdraw_ShortfallHonest() public {
        asset.mint(address(adapter), 200e6);
        adapter.deploy();
        uint256 got = adapter.withdraw(1_000e6, vault);
        assertEq(got, 200e6, "capped at supplied");
    }

    function test_Harvest_ForwardsCompRaw() public {
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        rewards.setClaimable(25e18);
        adapter.harvest();
        assertEq(comp.balanceOf(treasury), 25e18, "COMP forwarded raw");
    }

    function test_Deploy_RevertsWhenNothingToDeploy() public {
        vm.expectRevert(IProtocolAdapter.ProtocolAdapterNothingToDeploy.selector);
        adapter.deploy();
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                    VAULT-SPINE NAV INVARIANT (the HIGH fix)
//////////////////////////////////////////////////////////////////////////*//

contract CompoundVaultMock is VaultCore {
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

contract CompoundManagerMock is StrategyManager {
    function initialize(address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        StrategyManagerLib.__StrategyManager_init();
        InitializableLib.postInitializer(s);
    }
}

/// @title CompoundV3AdapterVaultNavTest
/// @notice Second adapter (Compound v3) proving the NAV-stability invariant through the unchanged
///         VaultCore + StrategyManager spine: `allocateToStrategy` moves idle vault assets into the
///         adapter via a bare ERC-20 transfer that does NOT call `deploy()`; because the adapter's
///         `totalAssetsManaged()` now counts its idle base-asset balance, the vault's share price is
///         UNCHANGED across BOTH the allocate (no deploy) step AND the subsequent deploy().
contract CompoundV3AdapterVaultNavTest is Test {
    MockAsset asset;
    MockComet comet;
    MockCompoundAdapter adapter;
    CompoundVaultMock vault;
    CompoundManagerMock mgr;

    address admin = address(0xAD);
    address user = address(0xA1);
    address treasury = address(0x7E0);
    uint256 constant DEPOSIT = 1_000e6;

    function setUp() public {
        asset = new MockAsset();
        comet = new MockComet(asset);

        vault = new CompoundVaultMock();
        vault.initialize(address(asset), admin);

        mgr = new CompoundManagerMock();
        mgr.initialize(admin);

        adapter = new MockCompoundAdapter();
        adapter.initialize(admin, address(comet), address(asset), address(vault), treasury);

        vm.startPrank(admin);
        vault.setStrategyManager(address(mgr));
        mgr.setVault(address(vault));
        mgr.addStrategy(address(adapter), 10_000); // 100% target
        // The StrategyManager is the adapter's authorized operator (deploy/withdraw/harvest).
        adapter.setOperator(address(mgr));
        vm.stopPrank();
    }

    /// @notice NAV is invariant across allocate (no deploy) AND deploy — no theft window, no
    ///         double-count. Pre-fix the Comet adapter reported 0 the instant funds were allocated
    ///         to it (idle, undeployed), cratering the vault's share price until a keeper deployed.
    function test_NavStableAcrossAllocateAndDeploy() public {
        asset.mint(user, DEPOSIT);
        vm.startPrank(user);
        asset.approve(address(vault), DEPOSIT);
        vault.deposit(DEPOSIT, user);
        vm.stopPrank();

        uint256 navBefore = vault.totalAssets();
        assertEq(navBefore, DEPOSIT, "NAV == deposit at rest");

        // Allocate: vault idle -> adapter idle (bare transfer, NO supply to Comet).
        mgr.rebalance();
        assertEq(asset.balanceOf(address(adapter)), DEPOSIT, "funds idle in adapter, not supplied");
        assertEq(comet.balanceOf(address(adapter)), 0, "nothing supplied to Comet yet");
        assertEq(adapter.totalAssetsManaged(), DEPOSIT, "adapter counts its idle");
        assertEq(vault.totalAssets(), navBefore, "NAV UNCHANGED across allocate (no deploy)");

        // Deploy: adapter idle -> Comet position. idle->0, Comet balance grows by the same amount.
        vm.prank(address(mgr));
        adapter.deploy();
        assertEq(asset.balanceOf(address(adapter)), 0, "adapter idle now supplied");
        assertEq(comet.balanceOf(address(adapter)), DEPOSIT, "supplied to Comet 1:1");
        assertEq(vault.totalAssets(), navBefore, "NAV STILL UNCHANGED across deploy (no double-count)");
    }
}
