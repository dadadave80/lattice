// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAPI3Adapter} from "@lattice/interfaces/IAPI3Adapter.sol";
import {IApi3Proxy} from "@lattice/interfaces/external/IApi3Proxy.sol";
import {API3Adapter} from "@lattice/oracles/API3Adapter.sol";
import {API3AdapterLib} from "@lattice/oracles/libraries/API3AdapterLib.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCKS
// ---------------------------------------------------------------------------

/// @notice Minimal mock API3 dAPI reader proxy with settable fields.
contract MockApi3Proxy is IApi3Proxy {
    int224 public value;
    uint32 public timestamp;

    function set(int224 _value, uint32 _timestamp) external {
        value = _value;
        timestamp = _timestamp;
    }

    function read() external view returns (int224, uint32) {
        return (value, timestamp);
    }
}

/// @notice Combines AccessControl + API3Adapter for testing.
contract MockAPI3AdapterContract is AccessControl, API3Adapter {
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        API3AdapterLib.__API3Adapter_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

contract API3AdapterTester is Test {
    MockAPI3AdapterContract adapter;
    MockApi3Proxy proxy;

    address admin = address(0x1);
    address user = address(0x2);

    bytes32 constant KEY_ETH_USD = keccak256("ETH/USD");
    bytes32 constant KEY_UNKNOWN = keccak256("UNKNOWN");

    uint48 constant MAX_STALENESS = 3600; // 1 hour
    int224 constant PRICE = 3000e18; // dAPIs are already 18-decimals

    function setUp() public {
        vm.warp(10_000);
        adapter = new MockAPI3AdapterContract();
        adapter.initialize(admin);

        proxy = new MockApi3Proxy();
        proxy.set(PRICE, uint32(block.timestamp - 5));
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
        adapter.registerFeed(KEY_ETH_USD, address(proxy), MAX_STALENESS);
    }

    function test_RegisterFeedByAdmin() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(proxy), MAX_STALENESS);

        (address storedProxy, uint48 storedStaleness) = adapter.getFeed(KEY_ETH_USD);
        assertEq(storedProxy, address(proxy));
        assertEq(storedStaleness, MAX_STALENESS);
    }

    function test_RegisterFeedEmitsFeedRegistered() public {
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit IAPI3Adapter.FeedRegistered(KEY_ETH_USD, address(proxy), MAX_STALENESS);
        adapter.registerFeed(KEY_ETH_USD, address(proxy), MAX_STALENESS);
    }

    function test_RegisterFeedRevertsOnZeroProxy() public {
        vm.prank(admin);
        vm.expectRevert(IAPI3Adapter.API3InvalidConfig.selector);
        adapter.registerFeed(KEY_ETH_USD, address(0), MAX_STALENESS);
    }

    function test_RegisterFeedRevertsOnZeroMaxStaleness() public {
        vm.prank(admin);
        vm.expectRevert(IAPI3Adapter.API3InvalidConfig.selector);
        adapter.registerFeed(KEY_ETH_USD, address(proxy), 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          LATEST ANSWER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice dAPI value (already 18-dec) is returned unchanged, only widened.
    function test_LatestAnswerAlreadyWad() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(proxy), MAX_STALENESS);
        assertEq(adapter.latestAnswer(KEY_ETH_USD), int256(PRICE));
    }

    function test_ReadReturnsNativeFields() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(proxy), MAX_STALENESS);

        (int224 value, uint32 timestamp) = adapter.read(KEY_ETH_USD);
        assertEq(value, PRICE);
        assertEq(timestamp, uint32(block.timestamp - 5));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            STALENESS TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_RevertsOnStaleData() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(proxy), MAX_STALENESS);

        uint32 staleTs = uint32(block.timestamp - MAX_STALENESS - 1);
        proxy.set(PRICE, staleTs);

        vm.expectRevert(
            abi.encodeWithSelector(IAPI3Adapter.API3StaleData.selector, KEY_ETH_USD, staleTs, MAX_STALENESS)
        );
        adapter.latestAnswer(KEY_ETH_USD);
    }

    function test_FutureTimestampRevertsStale() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(proxy), MAX_STALENESS);

        uint32 futureTs = uint32(block.timestamp + 100);
        proxy.set(PRICE, futureTs);

        vm.expectRevert(
            abi.encodeWithSelector(IAPI3Adapter.API3StaleData.selector, KEY_ETH_USD, futureTs, MAX_STALENESS)
        );
        adapter.latestAnswer(KEY_ETH_USD);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           INVALID ANSWER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_NegativeValueReverts() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(proxy), MAX_STALENESS);
        proxy.set(-1, uint32(block.timestamp - 5));

        vm.expectRevert(abi.encodeWithSelector(IAPI3Adapter.API3InvalidAnswer.selector, KEY_ETH_USD, int224(-1)));
        adapter.latestAnswer(KEY_ETH_USD);
    }

    function test_ZeroValueReverts() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(proxy), MAX_STALENESS);
        proxy.set(0, uint32(block.timestamp - 5));

        vm.expectRevert(abi.encodeWithSelector(IAPI3Adapter.API3InvalidAnswer.selector, KEY_ETH_USD, int224(0)));
        adapter.latestAnswer(KEY_ETH_USD);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     UNREGISTERED / UNREGISTER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_UnregisteredKeyReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IAPI3Adapter.API3FeedNotRegistered.selector, KEY_UNKNOWN));
        adapter.latestAnswer(KEY_UNKNOWN);
    }

    function test_UnregisterFeedWorks() public {
        vm.startPrank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(proxy), MAX_STALENESS);

        vm.expectEmit(true, false, false, false);
        emit IAPI3Adapter.FeedUnregistered(KEY_ETH_USD);
        adapter.unregisterFeed(KEY_ETH_USD);
        vm.stopPrank();

        (address storedProxy,) = adapter.getFeed(KEY_ETH_USD);
        assertEq(storedProxy, address(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_InterfaceId() public pure {
        assertEq(type(IAPI3Adapter).interfaceId, bytes4(0xfa98111e));
    }

    function test_SupportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IAPI3Adapter).interfaceId));
    }
}
