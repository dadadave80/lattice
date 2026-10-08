// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC4626Adapter} from "@lattice/defi/ERC4626Adapter.sol";
import {ERC4626AdapterLib} from "@lattice/defi/libraries/ERC4626AdapterLib.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
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
    // When set, `deposit` reverts (models a target vault at its deposit cap or paused).
    bool public depositsBlocked;

    constructor(MockAsset a) {
        _asset = a;
    }

    function asset() external view returns (address) {
        return address(_asset);
    }

    function setPricePerShare(uint256 p6) external {
        pricePerShare6 = p6;
    }

    function setDepositsBlocked(bool blocked) external {
        depositsBlocked = blocked;
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

    function maxWithdraw(address owner) external view returns (uint256) {
        return convertToAssets(balanceOf[owner]);
    }

    /// @dev Rounds shares up, as ERC-4626 requires of `previewWithdraw`.
    function previewWithdraw(uint256 assets) public view returns (uint256) {
        return (assets * 1e6 + pricePerShare6 - 1) / pricePerShare6;
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        shares = previewWithdraw(assets);
        require(balanceOf[owner] >= shares, "shares");
        balanceOf[owner] -= shares;
        totalSupply -= shares;
        require(_asset.transfer(receiver, assets), "send");
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        require(!depositsBlocked, "deposits blocked");
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

contract MockERC4626Adapter is ERC4626Adapter, Initializable {
    function initialize(address admin_, address target_, address asset_, address vault_, address recipient_)
        external
        initializer
    {
        AccessControlLib.__AccessControl_init(admin_);
        ERC4626AdapterLib.__ERC4626Adapter_init(target_, asset_, vault_, recipient_);
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

    /// @notice #221: at a non-integer price per share a recall delivers the exact amount. Converting the amount
    ///         to shares and redeeming them floors twice and under-delivers.
    function test_Withdraw_NonIntegerRate_DeliversExactAmount() public {
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        target.accrueYield(66_666_000); // price per share 1.066666
        uint256 got = adapter.withdraw(16_666_500, vault);
        assertEq(got, 16_666_500, "reported exact");
        assertEq(asset.balanceOf(vault), 16_666_500, "vault received exact");
    }

    /// @notice #221: a recall spends the adapter's undeployed idle before touching the position.
    function test_Withdraw_SpendsIdleBeforePosition() public {
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        uint256 shares = target.balanceOf(address(adapter));
        asset.mint(address(adapter), 300e6); // allocated, not yet deployed

        uint256 got = adapter.withdraw(200e6, vault);
        assertEq(got, 200e6, "paid from idle");
        assertEq(asset.balanceOf(vault), 200e6, "vault received");
        assertEq(target.balanceOf(address(adapter)), shares, "position untouched");
        assertEq(asset.balanceOf(address(adapter)), 100e6, "idle spent first");
    }

    /// @notice #221: a recall larger than idle drains idle, then withdraws the exact remainder from the position.
    function test_Withdraw_IdleThenPosition_NonIntegerRate() public {
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        target.accrueYield(66_666_000);
        asset.mint(address(adapter), 100e6);

        uint256 got = adapter.withdraw(250e6, vault);
        assertEq(got, 250e6, "idle + exact position withdraw");
        assertEq(asset.balanceOf(vault), 250e6, "vault received");
        assertEq(asset.balanceOf(address(adapter)), 0, "idle drained");
    }

    /// @notice #221: with only undeployed idle (no shares) the recall is paid in full from idle.
    function test_Withdraw_UndeployedIdleOnly() public {
        asset.mint(address(adapter), 500e6);
        uint256 got = adapter.withdraw(400e6, vault);
        assertEq(got, 400e6, "paid from idle");
        assertEq(asset.balanceOf(vault), 400e6, "vault received");
    }

    /// @notice #221: a request above `maxWithdraw` redeems every redeemable share instead.
    function test_Withdraw_AboveMaxWithdraw_RedeemsAllShares() public {
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        target.accrueYield(66_666_000);
        uint256 maxOut = target.maxWithdraw(address(adapter));
        uint256 got = adapter.withdraw(maxOut + 1, vault);
        assertEq(target.balanceOf(address(adapter)), 0, "all shares redeemed");
        assertEq(got, maxOut, "honest: everything the position held");
    }

    /// @notice #221: the emergency exit also returns the adapter's undeployed idle to the vault.
    function test_EmergencyWithdraw_SweepsIdle() public {
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
        asset.mint(address(adapter), 50e6);
        vm.prank(admin);
        uint256 recovered = adapter.emergencyWithdraw();
        assertEq(recovered, 1_050e6, "position + idle");
        assertEq(asset.balanceOf(vault), 1_050e6, "vault received both");
        assertEq(asset.balanceOf(address(adapter)), 0, "no idle left behind");
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
