// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IRedStoneAdapter} from "@lattice/interfaces/IRedStoneAdapter.sol";
import {IRedstonePriceFeedsAdapter} from "@lattice/interfaces/external/IRedstonePriceFeedsAdapter.sol";
import {RedStoneAdapter} from "@lattice/oracles/RedStoneAdapter.sol";
import {RedStoneAdapterLib} from "@lattice/oracles/libraries/RedStoneAdapterLib.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCKS
// ---------------------------------------------------------------------------

/// @notice Minimal mock RedStone PriceFeedsAdapter with a settable value and batch update time.
contract MockRedstoneAdapter is IRedstonePriceFeedsAdapter {
    uint256 public value;
    uint128 public dataTimestamp;
    uint128 public blockTimestamp;

    function set(uint256 _value, uint128 _blockTimestamp) external {
        value = _value;
        blockTimestamp = _blockTimestamp;
        dataTimestamp = _blockTimestamp * 1000; // RedStone data timestamps are in milliseconds
    }

    function getValueForDataFeed(bytes32) external view returns (uint256) {
        return value;
    }

    function getTimestampsFromLatestUpdate() external view returns (uint128, uint128) {
        return (dataTimestamp, blockTimestamp);
    }
}

/// @notice Combines AccessControl + RedStoneAdapter for testing.
contract MockRedStoneAdapterContract is AccessControl, RedStoneAdapter {
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        RedStoneAdapterLib.__RedStoneAdapter_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

contract RedStoneAdapterTester is Test {
    MockRedStoneAdapterContract adapter;
    MockRedstoneAdapter feed;

    address admin = address(0x1);
    address user = address(0x2);

    bytes32 constant KEY_ETH_USD = keccak256("ETH/USD");
    bytes32 constant KEY_UNKNOWN = keccak256("UNKNOWN");
    bytes32 constant DATA_FEED_ID = bytes32("ETH");

    uint48 constant MAX_STALENESS = 3600; // 1 hour
    uint256 constant PRICE = 3000e8; // RedStone Push values are 8-decimals

    function setUp() public {
        vm.warp(1_000_000);
        adapter = new MockRedStoneAdapterContract();
        adapter.initialize(admin);

        feed = new MockRedstoneAdapter();
        feed.set(PRICE, uint128(block.timestamp - 5));
    }

    function _register() internal {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(feed), DATA_FEED_ID, MAX_STALENESS);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          REGISTER FEED TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegisterFeedRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        adapter.registerFeed(KEY_ETH_USD, address(feed), DATA_FEED_ID, MAX_STALENESS);
    }

    function test_RegisterFeedByAdmin() public {
        _register();
        (address storedAdapter, bytes32 storedId, uint48 storedStaleness) = adapter.getFeed(KEY_ETH_USD);
        assertEq(storedAdapter, address(feed));
        assertEq(storedId, DATA_FEED_ID);
        assertEq(storedStaleness, MAX_STALENESS);
    }

    function test_RegisterFeedEmitsFeedRegistered() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IRedStoneAdapter.FeedRegistered(KEY_ETH_USD, address(feed), DATA_FEED_ID, MAX_STALENESS);
        adapter.registerFeed(KEY_ETH_USD, address(feed), DATA_FEED_ID, MAX_STALENESS);
    }

    function test_RegisterFeedRevertsOnZeroAdapter() public {
        vm.prank(admin);
        vm.expectRevert(IRedStoneAdapter.RedStoneInvalidConfig.selector);
        adapter.registerFeed(KEY_ETH_USD, address(0), DATA_FEED_ID, MAX_STALENESS);
    }

    function test_RegisterFeedRevertsOnZeroMaxStaleness() public {
        vm.prank(admin);
        vm.expectRevert(IRedStoneAdapter.RedStoneInvalidConfig.selector);
        adapter.registerFeed(KEY_ETH_USD, address(feed), DATA_FEED_ID, 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          LATEST ANSWER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice 8-decimal value is normalized to WAD (* 1e10).
    function test_LatestAnswer8DecimalNormalized() public {
        _register();
        // 3000e8 * 1e10 = 3000e18
        assertEq(adapter.latestAnswer(KEY_ETH_USD), int256(3000e18));
    }

    function test_GetValueForDataFeedReturnsNativeFields() public {
        _register();
        (uint256 value, uint256 timestamp) = adapter.getValueForDataFeed(KEY_ETH_USD);
        assertEq(value, PRICE);
        assertEq(timestamp, block.timestamp - 5);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            STALENESS TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_RevertsOnStaleData() public {
        _register();
        uint128 staleTs = uint128(block.timestamp - MAX_STALENESS - 1);
        feed.set(PRICE, staleTs);

        vm.expectRevert(
            abi.encodeWithSelector(IRedStoneAdapter.RedStoneStaleData.selector, KEY_ETH_USD, staleTs, MAX_STALENESS)
        );
        adapter.latestAnswer(KEY_ETH_USD);
    }

    function test_FutureTimestampRevertsStale() public {
        _register();
        uint128 futureTs = uint128(block.timestamp + 100);
        feed.set(PRICE, futureTs);

        vm.expectRevert(
            abi.encodeWithSelector(IRedStoneAdapter.RedStoneStaleData.selector, KEY_ETH_USD, futureTs, MAX_STALENESS)
        );
        adapter.latestAnswer(KEY_ETH_USD);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           INVALID ANSWER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_ZeroValueReverts() public {
        _register();
        feed.set(0, uint128(block.timestamp - 5));

        vm.expectRevert(
            abi.encodeWithSelector(IRedStoneAdapter.RedStoneInvalidAnswer.selector, KEY_ETH_USD, uint256(0))
        );
        adapter.latestAnswer(KEY_ETH_USD);
    }

    /// @notice A value large enough to overflow int256 after the 1e10 scale is rejected, not wrapped.
    function test_OverflowValueReverts() public {
        _register();
        uint256 huge = uint256(type(int256).max) / 1e10 + 1;
        feed.set(huge, uint128(block.timestamp - 5));

        vm.expectRevert(abi.encodeWithSelector(IRedStoneAdapter.RedStoneInvalidAnswer.selector, KEY_ETH_USD, huge));
        adapter.latestAnswer(KEY_ETH_USD);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     UNREGISTERED / UNREGISTER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_UnregisteredKeyReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IRedStoneAdapter.RedStoneFeedNotRegistered.selector, KEY_UNKNOWN));
        adapter.latestAnswer(KEY_UNKNOWN);
    }

    function test_UnregisterFeedWorks() public {
        _register();
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit IRedStoneAdapter.FeedUnregistered(KEY_ETH_USD);
        adapter.unregisterFeed(KEY_ETH_USD);

        (address storedAdapter,,) = adapter.getFeed(KEY_ETH_USD);
        assertEq(storedAdapter, address(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_InterfaceId() public pure {
        assertEq(type(IRedStoneAdapter).interfaceId, bytes4(0xd5afaecd));
    }

    function test_SupportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IRedStoneAdapter).interfaceId));
    }
}
