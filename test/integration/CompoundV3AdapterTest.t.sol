// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {CompoundV3Adapter} from "@lattice/defi/CompoundV3Adapter.sol";
import {CompoundV3AdapterLib} from "@lattice/defi/libraries/CompoundV3AdapterLib.sol";
import {IProtocolAdapter} from "@lattice/interfaces/IProtocolAdapter.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
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
        vm.prank(admin);
        adapter.setCometRewards(address(rewards));
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
