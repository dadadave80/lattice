// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC4626Adapter} from "@lattice/defi/ERC4626Adapter.sol";
import {ERC4626AdapterLib} from "@lattice/defi/libraries/ERC4626AdapterLib.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {Test} from "forge-std/Test.sol";

import {MockAsset} from "./AaveV3AdapterSupplyTest.t.sol";

//*//////////////////////////////////////////////////////////////////////////
//                      MOCK ERC4626 TARGET VAULT
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal ERC4626 with a configurable exchange rate (shares <-> assets) to model yield.
contract MockERC4626 {
    MockAsset public immutable _asset;
    string public name = "yVault";
    string public symbol = "yV";
    uint8 public decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    // assets-per-share scaled by 1e6 (starts 1:1).
    uint256 public pricePerShare6 = 1e6;

    constructor(MockAsset a) {
        _asset = a;
    }

    function asset() external view returns (address) {
        return address(_asset);
    }

    function setPricePerShare(uint256 p6) external {
        pricePerShare6 = p6;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return shares * pricePerShare6 / 1e6;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return assets * 1e6 / pricePerShare6;
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return balanceOf[owner];
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        require(_asset.transferFrom(msg.sender, address(this), assets), "pull");
        shares = convertToShares(assets);
        balanceOf[receiver] += shares;
        totalSupply += shares;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        require(balanceOf[owner] >= shares, "shares");
        assets = convertToAssets(shares);
        balanceOf[owner] -= shares;
        totalSupply -= shares;
        require(_asset.transfer(receiver, assets), "send");
    }

    /// @dev simulate yield: each share now worth more.
    function accrueYield(uint256 extraAssets) external {
        _asset.mint(address(this), extraAssets);
        if (totalSupply > 0) pricePerShare6 += extraAssets * 1e6 / totalSupply;
    }
}

contract MockSideReward {
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

contract MockERC4626Adapter is ERC4626Adapter {
    function initialize(address admin_, address target_, address asset_, address vault_, address recipient_) external {
        bytes32 s = InitializableLib.initializableSlot();
        s = InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        ReentrancyGuardLib.__ReentrancyGuard_init();
        ERC4626AdapterLib.__ERC4626Adapter_init(target_, asset_, vault_, recipient_);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) external view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

contract ERC4626AdapterTest is Test {
    MockAsset asset;
    MockERC4626 target;
    MockERC4626Adapter adapter;
    address admin = address(0xAD);
    address vault = address(0x7A17);
    address treasury = address(0x7E0);

    function setUp() public {
        asset = new MockAsset();
        target = new MockERC4626(asset);
        adapter = new MockERC4626Adapter();
        adapter.initialize(admin, address(target), address(asset), vault, treasury);
        // Authorize this test contract as the operator so the direct deploy/withdraw/harvest calls
        // (which the StrategyManager would make in production) pass the operator gate.
        vm.prank(admin);
        adapter.setOperator(address(this));
    }

    function test_Deploy_DepositsIntoTargetVault() public {
        asset.mint(address(adapter), 1_000e6);
        uint256 deployed = adapter.deploy();
        assertEq(deployed, 1_000e6);
        assertEq(adapter.totalAssetsManaged(), 1_000e6, "NAV at 1:1");
    }

    function test_TotalAssets_TracksConvertToAssetsAfterYield() public {
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        target.accrueYield(100e6); // +10% NAV
        assertApproxEqAbs(adapter.totalAssetsManaged(), 1_100e6, 2, "NAV grows with pricePerShare");
    }

    function test_Withdraw_RedeemsSharesHonoringNav() public {
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        uint256 got = adapter.withdraw(400e6, vault);
        assertApproxEqAbs(got, 400e6, 2, "redeemed ~400 assets");
        assertApproxEqAbs(asset.balanceOf(vault), 400e6, 2, "vault received");
    }

    function test_Withdraw_ShortfallHonestWhenRequestExceedsNav() public {
        asset.mint(address(adapter), 200e6);
        adapter.deploy();
        uint256 got = adapter.withdraw(1_000e6, vault);
        assertApproxEqAbs(got, 200e6, 2, "capped at NAV");
    }

    function test_Harvest_ForwardsSideRewardRawWhenSet() public {
        MockSideReward side = new MockSideReward();
        vm.prank(admin);
        adapter.setSideRewardToken(address(side));
        side.mint(address(adapter), 33e18); // a side token landed on the adapter
        adapter.harvest();
        assertEq(side.balanceOf(treasury), 33e18, "side reward forwarded raw");
    }

    function test_Harvest_NoSideTokenIsNoOp() public {
        adapter.harvest(); // must not revert when no side token configured
    }

    function test_HealthFactor_MaxNoLeverage() public view {
        assertEq(adapter.healthFactor(), type(uint256).max);
        assertEq(adapter.minHealthFactor(), type(uint256).max);
    }

    function test_Deploy_RevertsWhenNothingToDeploy() public {
        vm.expectRevert(IProtocolAdapter.ProtocolAdapterNothingToDeploy.selector);
        adapter.deploy();
    }
}
