// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IPythAdapter} from "@lattice/interfaces/IPythAdapter.sol";
import {IPyth} from "@lattice/interfaces/external/IPyth.sol";
import {PythAdapter} from "@lattice/oracles/PythAdapter.sol";
import {PythAdapterLib} from "@lattice/oracles/libraries/PythAdapterLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Minimal mock Pyth with settable price + fee, tracking received ETH.
contract MockPyth is IPyth {
    mapping(bytes32 id => Price) internal _prices;
    uint256 public fee;
    uint256 public received;

    function setPrice(bytes32 id, int64 price, uint64 conf, int32 expo, uint256 publishTime) external {
        _prices[id] = Price({price: price, conf: conf, expo: expo, publishTime: publishTime});
    }

    function setFee(uint256 f) external {
        fee = f;
    }

    function getPriceUnsafe(bytes32 id) external view returns (Price memory) {
        return _prices[id];
    }

    function getUpdateFee(bytes[] calldata) external view returns (uint256) {
        return fee;
    }

    function updatePriceFeeds(bytes[] calldata) external payable {
        received += msg.value;
    }
}

/// @notice Combines AccessControl + PythAdapter for testing.
contract MockPythAdapterContract is AccessControl, PythAdapter {
    function initialize(address admin, address pyth_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin);
        PythAdapterLib.__PythAdapter_init(pyth_);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }

    receive() external payable {}
}

/// @title PythAdapterTester
/// @notice Unit tests for the Pyth price-oracle adapter against a mock Pyth.
contract PythAdapterTester is Test {
    MockPythAdapterContract adapter;
    MockPyth pyth;
    address admin = address(0xA11CE);

    bytes32 constant KEY = keccak256("ETH/USD");
    bytes32 constant PRICE_ID = bytes32(uint256(0xE7));
    uint48 constant STALENESS = 3600;
    uint64 constant CONF_BPS = 100; // 1%

    function setUp() public {
        pyth = new MockPyth();
        adapter = new MockPythAdapterContract();
        adapter.initialize(admin, address(pyth));
        vm.warp(1_000_000);
        vm.prank(admin);
        adapter.registerFeed(KEY, PRICE_ID, STALENESS, CONF_BPS);
    }

    function _setPrice(int64 price, uint64 conf, int32 expo) internal {
        pyth.setPrice(PRICE_ID, price, conf, expo, block.timestamp);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegisterAndGetFeed() public view {
        (bytes32 priceId, uint48 maxStaleness, uint64 maxConfBps) = adapter.getFeed(KEY);
        assertEq(priceId, PRICE_ID);
        assertEq(maxStaleness, STALENESS);
        assertEq(maxConfBps, CONF_BPS);
        assertEq(adapter.pyth(), address(pyth));
    }

    function test_LatestAnswerNormalizesExpoNeg8() public {
        // $2000 with expo -8: price = 2000e8, WAD = 2000e8 * 1e10 = 2000e18.
        _setPrice(2000e8, 1e6, -8);
        assertEq(adapter.latestAnswer(KEY), 2000e18);
    }

    function test_LatestAnswerExpo0() public {
        _setPrice(5, 0, 0); // WAD = 5 * 1e18
        assertEq(adapter.latestAnswer(KEY), 5e18);
    }

    function test_LatestAnswerExpoNeg18() public {
        _setPrice(3e18, 0, -18); // e = 0 -> WAD = price
        assertEq(adapter.latestAnswer(KEY), 3e18);
    }

    function test_LatestAnswerExpoBelowWad() public {
        _setPrice(3e18, 0, -20); // e = -2 -> WAD = price / 100 = 3e16
        assertEq(adapter.latestAnswer(KEY), 3e16);
    }

    function test_LatestAnswerRaw() public {
        _setPrice(2000e8, 7, -8);
        (int64 price, int32 expo, uint64 conf, uint256 publishTime) = adapter.latestAnswerRaw(KEY);
        assertEq(price, 2000e8);
        assertEq(expo, -8);
        assertEq(conf, 7);
        assertEq(publishTime, block.timestamp);
    }

    function test_ExpoOutOfRangeReverts() public {
        _setPrice(1, 0, 19); // e = 37 > 36
        vm.expectRevert(abi.encodeWithSelector(IPythAdapter.PythExpoOutOfRange.selector, int32(19)));
        adapter.latestAnswer(KEY);
    }

    function test_InvalidAnswerReverts() public {
        _setPrice(0, 0, -8);
        vm.expectRevert(abi.encodeWithSelector(IPythAdapter.PythInvalidAnswer.selector, KEY, int64(0)));
        adapter.latestAnswer(KEY);
        _setPrice(-1, 0, -8);
        vm.expectRevert(abi.encodeWithSelector(IPythAdapter.PythInvalidAnswer.selector, KEY, int64(-1)));
        adapter.latestAnswer(KEY);
    }

    function test_StalePriceReverts() public {
        _setPrice(2000e8, 0, -8);
        uint256 publishTime = block.timestamp;
        vm.warp(block.timestamp + STALENESS + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IPythAdapter.PythStaleData.selector, KEY, publishTime, uint256(STALENESS))
        );
        adapter.latestAnswer(KEY);
    }

    function test_FuturePriceReverts() public {
        pyth.setPrice(PRICE_ID, 2000e8, 0, -8, block.timestamp + 1);
        vm.expectRevert(abi.encodeWithSelector(IPythAdapter.PythFuturePrice.selector, KEY, block.timestamp + 1));
        adapter.latestAnswer(KEY);
    }

    function test_ConfidenceWithinBoundOk() public {
        // conf/price = 5/1000 = 50 bps <= 100 bps.
        _setPrice(1000, 5, 0);
        assertEq(adapter.latestAnswer(KEY), 1000e18);
    }

    function test_ConfidenceTooWideReverts() public {
        // conf/price = 50/1000 = 500 bps > 100 bps.
        _setPrice(1000, 50, 0);
        vm.expectRevert(
            abi.encodeWithSelector(IPythAdapter.PythConfidenceTooWide.selector, KEY, uint64(50), int64(1000), CONF_BPS)
        );
        adapter.latestAnswer(KEY);
    }

    function test_ConfidenceDisabledWhenZero() public {
        vm.prank(admin);
        adapter.registerFeed(KEY, PRICE_ID, STALENESS, 0); // maxConfBps 0 disables
        _setPrice(1000, 999, 0); // huge conf, but check disabled
        assertEq(adapter.latestAnswer(KEY), 1000e18);
    }

    function test_FeedNotRegisteredReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IPythAdapter.PythFeedNotRegistered.selector, keccak256("X")));
        adapter.latestAnswer(keccak256("X"));
    }

    function test_UnregisterFeed() public {
        vm.prank(admin);
        adapter.unregisterFeed(KEY);
        (, uint48 maxStaleness,) = adapter.getFeed(KEY);
        assertEq(maxStaleness, 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              UPDATE PATH
    //////////////////////////////////////////////////////////////////////////*//

    function test_UpdatePriceFeedsForwardsFeeAndRefunds() public {
        pyth.setFee(100);
        bytes[] memory data = new bytes[](1);
        data[0] = hex"deadbeef";
        uint256 balBefore = address(this).balance;

        adapter.updatePriceFeeds{value: 150}(data);

        assertEq(pyth.received(), 100, "pyth got fee");
        assertEq(address(this).balance, balBefore - 100, "caller charged exactly the fee (50 refunded)");
    }

    function test_UpdatePriceFeedsInsufficientFeeReverts() public {
        pyth.setFee(100);
        bytes[] memory data = new bytes[](1);
        vm.expectRevert(abi.encodeWithSelector(IPythAdapter.PythInsufficientFee.selector, uint256(50), uint256(100)));
        adapter.updatePriceFeeds{value: 50}(data);
    }

    function test_GetUpdateFee() public {
        pyth.setFee(42);
        bytes[] memory data = new bytes[](1);
        assertEq(adapter.getUpdateFee(data), 42);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ADMIN / ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegisterFeedOnlyAdmin() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        adapter.registerFeed(KEY, PRICE_ID, STALENESS, CONF_BPS);
    }

    function test_RegisterInvalidConfigReverts() public {
        vm.startPrank(admin);
        vm.expectRevert(IPythAdapter.PythInvalidConfig.selector);
        adapter.registerFeed(KEY, bytes32(0), STALENESS, CONF_BPS); // zero priceId
        vm.expectRevert(IPythAdapter.PythInvalidConfig.selector);
        adapter.registerFeed(KEY, PRICE_ID, 0, CONF_BPS); // zero staleness
        vm.stopPrank();
    }

    function test_SetPyth() public {
        MockPyth p2 = new MockPyth();
        vm.prank(admin);
        adapter.setPyth(address(p2));
        assertEq(adapter.pyth(), address(p2));
    }

    function test_SetPythOnlyAdmin() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        adapter.setPyth(address(0xC0FFEE));
    }

    function test_SetPythZeroReverts() public {
        vm.prank(admin);
        vm.expectRevert(IPythAdapter.PythContractIsZero.selector);
        adapter.setPyth(address(0));
    }

    function test_InterfaceIdMatchesConstant() public pure {
        assertEq(type(IPythAdapter).interfaceId, bytes4(0x3839468c), "IPythAdapter interfaceId moved");
    }

    function test_SupportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IPythAdapter).interfaceId));
    }

    receive() external payable {}
}
