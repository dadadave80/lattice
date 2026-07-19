// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AaveV3Adapter} from "@lattice/defi/AaveV3Adapter.sol";
import {AaveV3AdapterLib} from "@lattice/defi/libraries/AaveV3AdapterLib.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

import {MockAToken, MockAaveV3Pool, MockAsset} from "./AaveV3AdapterSupplyTest.t.sol";

//*//////////////////////////////////////////////////////////////////////////
//                          MOCK REWARD TOKENS
//////////////////////////////////////////////////////////////////////////*//

contract MockRewardToken {
    string public name = "Reward";
    string public symbol = "RWD";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 a) external {
        balanceOf[to] += a;
    }

    function transfer(address to, uint256 a) external virtual returns (bool) {
        require(balanceOf[msg.sender] >= a, "bal");
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
        return true;
    }

    function approve(address, uint256) external returns (bool) {
        return true;
    }
}

contract MockFeeReward is MockRewardToken {
    function transfer(address to, uint256 a) public override returns (bool) {
        require(balanceOf[msg.sender] >= a, "bal");
        uint256 fee = a / 10;
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a - fee;
        balanceOf[address(0xdead)] += fee;
        return true;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                       MOCK REWARDS CONTROLLER
//////////////////////////////////////////////////////////////////////////*//

/// @notice Mints a preconfigured reward amount to `to` on claim, returning the list/amounts.
contract MockRewardsController {
    MockRewardToken public reward;
    uint256 public claimable;

    constructor(MockRewardToken r) {
        reward = r;
    }

    function setClaimable(uint256 a) external {
        claimable = a;
    }

    function claimAllRewards(address[] calldata, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory amounts)
    {
        rewardsList = new address[](1);
        rewardsList[0] = address(reward);
        amounts = new uint256[](1);
        amounts[0] = claimable;
        if (claimable > 0) reward.mint(to, claimable);
        claimable = 0;
    }
}

contract MockRewardAdapter is AaveV3Adapter, Initializable {
    function initialize(
        address admin_,
        address provider_,
        address asset_,
        address vault_,
        address rewardRecipient_,
        bytes32 feedKey_,
        uint256 minHf_
    ) external initializer {
        AccessControlLib.__AccessControl_init(admin_);
        ReentrancyGuardLib.__ReentrancyGuard_init();
        AaveV3AdapterLib.__AaveV3Adapter_init(provider_, asset_, vault_, rewardRecipient_, feedKey_, minHf_);
    }

    function supportsInterface(bytes4 id) external view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

contract AaveV3AdapterRewardsTest is Test {
    MockAsset asset;
    MockAToken aToken;
    MockAaveV3Pool pool;
    MockRewardAdapter adapter;
    MockRewardToken reward;
    MockRewardsController controller;

    address admin = address(0xAD);
    address vault = address(0x7A17);
    address treasury = address(0x7E0);
    bytes32 constant FEED_KEY = keccak256("USDC/USD");

    function setUp() public {
        asset = new MockAsset();
        aToken = new MockAToken(asset);
        pool = new MockAaveV3Pool();
        pool.setAToken(asset, aToken);
        reward = new MockRewardToken();
        controller = new MockRewardsController(reward);

        adapter = new MockRewardAdapter();
        adapter.initialize(admin, address(pool), address(asset), vault, treasury, FEED_KEY, 1.05e18);
        vm.prank(admin);
        adapter.setRewardsController(address(controller));
        // Authorize this test contract as the operator so the direct deploy/withdraw/harvest calls
        // (which the StrategyManager would make in production) pass the operator gate.
        vm.prank(admin);
        adapter.setOperator(address(this));

        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
    }

    function test_Harvest_ForwardsRewardsRawToRecipient() public {
        controller.setClaimable(50e18);
        adapter.harvest();
        assertEq(reward.balanceOf(treasury), 50e18, "recipient got raw reward");
        assertEq(reward.balanceOf(address(adapter)), 0, "adapter holds no reward");
    }

    function test_Harvest_ZeroClaimIsNoOpAndDoesNotRevert() public {
        controller.setClaimable(0);
        adapter.harvest(); // must not revert
        assertEq(reward.balanceOf(treasury), 0, "nothing forwarded");
    }

    function test_Harvest_RewardsNeverCountedInTotalAssets() public {
        controller.setClaimable(123e18);
        adapter.harvest();
        // totalAssetsManaged remains the supplied balance; rewards are unpriced and excluded.
        assertEq(adapter.totalAssetsManaged(), 1_000e6, "rewards excluded from NAV");
    }

    function test_Harvest_FeeOnTransferRewardDoesNotBrick() public {
        // Swap in a fee-on-transfer reward; harvest must still succeed and forward the net.
        MockFeeReward feeReward = new MockFeeReward();
        MockRewardsController feeCtrl = new MockRewardsController(MockRewardToken(address(feeReward)));
        vm.prank(admin);
        adapter.setRewardsController(address(feeCtrl));
        feeCtrl.setClaimable(100e18);

        adapter.harvest(); // no revert
        assertEq(feeReward.balanceOf(treasury), 90e18, "recipient nets 90% (fee-on-transfer)");
    }

    function test_Withdraw_StillWorksAfterBadRewardToken() public {
        MockFeeReward feeReward = new MockFeeReward();
        MockRewardsController feeCtrl = new MockRewardsController(MockRewardToken(address(feeReward)));
        vm.prank(admin);
        adapter.setRewardsController(address(feeCtrl));
        feeCtrl.setClaimable(100e18);
        adapter.harvest();

        uint256 got = adapter.withdraw(500e6, vault);
        assertEq(got, 500e6, "withdraw unaffected by reward token");
    }
}
