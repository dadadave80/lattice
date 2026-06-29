// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IChronicle} from "@lattice/interfaces/external/IChronicle.sol";
import {IChronicleAdapter} from "@lattice/interfaces/oracles/IChronicleAdapter.sol";
import {ChronicleAdapter} from "@lattice/oracles/ChronicleAdapter.sol";
import {ChronicleAdapterLib} from "@lattice/oracles/libraries/ChronicleAdapterLib.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCKS
// ---------------------------------------------------------------------------

/// @notice Minimal mock Chronicle oracle with settable value and age.
contract MockChronicle is IChronicle {
    uint256 public value;
    uint256 public age;

    function set(uint256 _value, uint256 _age) external {
        value = _value;
        age = _age;
    }

    function read() external view returns (uint256) {
        return value;
    }

    function readWithAge() external view returns (uint256, uint256) {
        return (value, age);
    }
}

/// @notice Combines AccessControl + ChronicleAdapter for testing.
contract MockChronicleAdapterContract is AccessControl, ChronicleAdapter {
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        ChronicleAdapterLib.__ChronicleAdapter_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

contract ChronicleAdapterTester is Test {
    MockChronicleAdapterContract adapter;
    MockChronicle chronicle;

    address admin = address(0x1);
    address user = address(0x2);

    bytes32 constant KEY_ETH_USD = keccak256("ETH/USD");
    bytes32 constant KEY_UNKNOWN = keccak256("UNKNOWN");

    uint48 constant MAX_STALENESS = 3600; // 1 hour
    uint256 constant PRICE = 3000e18; // Chronicle values are already 18-decimals (WAD)

    function setUp() public {
        vm.warp(10_000);
        adapter = new MockChronicleAdapterContract();
        adapter.initialize(admin);

        chronicle = new MockChronicle();
        chronicle.set(PRICE, block.timestamp - 5);
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
        adapter.registerFeed(KEY_ETH_USD, address(chronicle), MAX_STALENESS);
    }

    function test_RegisterFeedByAdmin() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(chronicle), MAX_STALENESS);

        (address storedChronicle, uint48 storedStaleness) = adapter.getFeed(KEY_ETH_USD);
        assertEq(storedChronicle, address(chronicle));
        assertEq(storedStaleness, MAX_STALENESS);
    }

    function test_RegisterFeedEmitsFeedRegistered() public {
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit IChronicleAdapter.FeedRegistered(KEY_ETH_USD, address(chronicle), MAX_STALENESS);
        adapter.registerFeed(KEY_ETH_USD, address(chronicle), MAX_STALENESS);
    }

    function test_RegisterFeedRevertsOnZeroChronicle() public {
        vm.prank(admin);
        vm.expectRevert(IChronicleAdapter.ChronicleInvalidConfig.selector);
        adapter.registerFeed(KEY_ETH_USD, address(0), MAX_STALENESS);
    }

    function test_RegisterFeedRevertsOnZeroMaxStaleness() public {
        vm.prank(admin);
        vm.expectRevert(IChronicleAdapter.ChronicleInvalidConfig.selector);
        adapter.registerFeed(KEY_ETH_USD, address(chronicle), 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          LATEST ANSWER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Chronicle value (already 18-dec) is returned unchanged, only cast to int256.
    function test_LatestAnswerAlreadyWad() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(chronicle), MAX_STALENESS);
        assertEq(adapter.latestAnswer(KEY_ETH_USD), int256(PRICE));
    }

    function test_ReadWithAgeReturnsNativeFields() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(chronicle), MAX_STALENESS);

        (uint256 value, uint256 age) = adapter.readWithAge(KEY_ETH_USD);
        assertEq(value, PRICE);
        assertEq(age, block.timestamp - 5);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            STALENESS TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_RevertsOnStaleData() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(chronicle), MAX_STALENESS);

        uint256 staleAge = block.timestamp - MAX_STALENESS - 1;
        chronicle.set(PRICE, staleAge);

        vm.expectRevert(
            abi.encodeWithSelector(IChronicleAdapter.ChronicleStaleData.selector, KEY_ETH_USD, staleAge, MAX_STALENESS)
        );
        adapter.latestAnswer(KEY_ETH_USD);
    }

    function test_FutureAgeRevertsStale() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(chronicle), MAX_STALENESS);

        uint256 futureAge = block.timestamp + 100;
        chronicle.set(PRICE, futureAge);

        vm.expectRevert(
            abi.encodeWithSelector(IChronicleAdapter.ChronicleStaleData.selector, KEY_ETH_USD, futureAge, MAX_STALENESS)
        );
        adapter.latestAnswer(KEY_ETH_USD);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           INVALID ANSWER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_ZeroValueReverts() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(chronicle), MAX_STALENESS);
        chronicle.set(0, block.timestamp - 5);

        vm.expectRevert(
            abi.encodeWithSelector(IChronicleAdapter.ChronicleInvalidAnswer.selector, KEY_ETH_USD, uint256(0))
        );
        adapter.latestAnswer(KEY_ETH_USD);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     UNREGISTERED / UNREGISTER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_UnregisteredKeyReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IChronicleAdapter.ChronicleFeedNotRegistered.selector, KEY_UNKNOWN));
        adapter.latestAnswer(KEY_UNKNOWN);
    }

    function test_UnregisterFeedWorks() public {
        vm.startPrank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(chronicle), MAX_STALENESS);

        vm.expectEmit(true, false, false, false);
        emit IChronicleAdapter.FeedUnregistered(KEY_ETH_USD);
        adapter.unregisterFeed(KEY_ETH_USD);
        vm.stopPrank();

        (address storedChronicle,) = adapter.getFeed(KEY_ETH_USD);
        assertEq(storedChronicle, address(0));
    }

    /// @notice A value >= 2^255 (which would wrap to a negative int256) is rejected, not cast.
    function test_OverflowValueReverts() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(chronicle), MAX_STALENESS);

        uint256 huge = uint256(type(int256).max) + 1; // 2^255
        chronicle.set(huge, block.timestamp - 5);

        vm.expectRevert(abi.encodeWithSelector(IChronicleAdapter.ChronicleInvalidAnswer.selector, KEY_ETH_USD, huge));
        adapter.latestAnswer(KEY_ETH_USD);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_InterfaceId() public pure {
        assertEq(type(IChronicleAdapter).interfaceId, bytes4(0x278f5b6a));
    }

    function test_SupportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IChronicleAdapter).interfaceId));
    }
}
