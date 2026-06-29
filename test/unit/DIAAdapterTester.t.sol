// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IDIAOracleV2} from "@lattice/interfaces/external/IDIAOracleV2.sol";
import {IDIAAdapter} from "@lattice/interfaces/oracles/IDIAAdapter.sol";
import {DIAAdapter} from "@lattice/oracles/DIAAdapter.sol";
import {DIAAdapterLib} from "@lattice/oracles/libraries/DIAAdapterLib.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCKS
// ---------------------------------------------------------------------------

/// @notice Minimal mock DIA OracleV2 with settable value/timestamp per key.
contract MockDIAOracle is IDIAOracleV2 {
    uint128 public defaultValue;
    uint128 public defaultTimestamp;

    mapping(string => uint128) private _values;
    mapping(string => uint128) private _timestamps;
    mapping(string => bool) private _hasOverride;

    function set(uint128 _value, uint128 _timestamp) external {
        defaultValue = _value;
        defaultTimestamp = _timestamp;
    }

    function setForKey(string calldata key, uint128 _value, uint128 _timestamp) external {
        _values[key] = _value;
        _timestamps[key] = _timestamp;
        _hasOverride[key] = true;
    }

    function getValue(string memory key) external view returns (uint128 value, uint128 timestamp) {
        if (_hasOverride[key]) {
            return (_values[key], _timestamps[key]);
        }
        return (defaultValue, defaultTimestamp);
    }
}

/// @notice Combines AccessControl + DIAAdapter for testing.
contract MockDIAAdapterContract is AccessControl, DIAAdapter {
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        DIAAdapterLib.__DIAAdapter_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

contract DIAAdapterTester is Test {
    MockDIAAdapterContract adapter;
    MockDIAOracle oracle;

    address admin = address(0x1);
    address user = address(0x2);

    bytes32 constant KEY_ETH_USD = keccak256("ETH/USD");
    bytes32 constant KEY_UNKNOWN = keccak256("UNKNOWN");

    string constant DIA_KEY = "ETH/USD";
    uint48 constant MAX_STALENESS = 3600; // 1 hour

    /// @dev DIA uses 8 decimals: 3000e8 == $3,000.
    uint128 constant PRICE_8DEC = 3000e8;

    function setUp() public {
        vm.warp(10_000);
        adapter = new MockDIAAdapterContract();
        adapter.initialize(admin);

        oracle = new MockDIAOracle();
        oracle.set(PRICE_8DEC, uint128(block.timestamp - 5));
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
        adapter.registerFeed(KEY_ETH_USD, address(oracle), DIA_KEY, MAX_STALENESS);
    }

    function test_RegisterFeedByAdmin() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(oracle), DIA_KEY, MAX_STALENESS);

        (address storedOracle, string memory storedKey, uint48 storedStaleness) = adapter.getFeed(KEY_ETH_USD);
        assertEq(storedOracle, address(oracle));
        assertEq(storedKey, DIA_KEY);
        assertEq(storedStaleness, MAX_STALENESS);
    }

    function test_RegisterFeedEmitsFeedRegistered() public {
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit IDIAAdapter.FeedRegistered(KEY_ETH_USD, address(oracle), DIA_KEY, MAX_STALENESS);
        adapter.registerFeed(KEY_ETH_USD, address(oracle), DIA_KEY, MAX_STALENESS);
    }

    function test_RegisterFeedRevertsOnZeroOracle() public {
        vm.prank(admin);
        vm.expectRevert(IDIAAdapter.DIAInvalidConfig.selector);
        adapter.registerFeed(KEY_ETH_USD, address(0), DIA_KEY, MAX_STALENESS);
    }

    function test_RegisterFeedRevertsOnEmptyDiaKey() public {
        vm.prank(admin);
        vm.expectRevert(IDIAAdapter.DIAInvalidConfig.selector);
        adapter.registerFeed(KEY_ETH_USD, address(oracle), "", MAX_STALENESS);
    }

    function test_RegisterFeedRevertsOnZeroMaxStaleness() public {
        vm.prank(admin);
        vm.expectRevert(IDIAAdapter.DIAInvalidConfig.selector);
        adapter.registerFeed(KEY_ETH_USD, address(oracle), DIA_KEY, 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          LATEST ANSWER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice DIA 8-decimal value 3000e8 normalizes to WAD 3000e18.
    function test_LatestAnswer8DecToWad() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(oracle), DIA_KEY, MAX_STALENESS);

        int256 answerWad = adapter.latestAnswer(KEY_ETH_USD);
        // 3000e8 * 1e10 == 3000e18
        assertEq(answerWad, int256(3000e18));
    }

    function test_LatestAnswerScaling() public {
        // Use a different 8-decimal price to confirm the scaling arithmetic
        oracle.set(150050e8, uint128(block.timestamp - 5)); // $150,050.00

        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(oracle), DIA_KEY, MAX_STALENESS);

        assertEq(adapter.latestAnswer(KEY_ETH_USD), int256(150050e18));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          GET VALUE (NATIVE) TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_GetValueReturnsNativeFields() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(oracle), DIA_KEY, MAX_STALENESS);

        (uint128 value, uint128 timestamp) = adapter.getValue(KEY_ETH_USD);
        assertEq(value, PRICE_8DEC);
        assertEq(timestamp, uint128(block.timestamp - 5));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            STALENESS TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_RevertsOnStaleData() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(oracle), DIA_KEY, MAX_STALENESS);

        uint128 staleTs = uint128(block.timestamp - MAX_STALENESS - 1);
        oracle.set(PRICE_8DEC, staleTs);

        vm.expectRevert(abi.encodeWithSelector(IDIAAdapter.DIAStaleData.selector, KEY_ETH_USD, staleTs, MAX_STALENESS));
        adapter.latestAnswer(KEY_ETH_USD);
    }

    function test_FutureTimestampRevertsStale() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(oracle), DIA_KEY, MAX_STALENESS);

        uint128 futureTs = uint128(block.timestamp + 100);
        oracle.set(PRICE_8DEC, futureTs);

        vm.expectRevert(abi.encodeWithSelector(IDIAAdapter.DIAStaleData.selector, KEY_ETH_USD, futureTs, MAX_STALENESS));
        adapter.latestAnswer(KEY_ETH_USD);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           INVALID ANSWER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_ZeroValueReverts() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(oracle), DIA_KEY, MAX_STALENESS);
        oracle.set(0, uint128(block.timestamp - 5));

        vm.expectRevert(abi.encodeWithSelector(IDIAAdapter.DIAInvalidAnswer.selector, KEY_ETH_USD, uint128(0)));
        adapter.latestAnswer(KEY_ETH_USD);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     UNREGISTERED / UNREGISTER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_UnregisteredKeyReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IDIAAdapter.DIAFeedNotRegistered.selector, KEY_UNKNOWN));
        adapter.latestAnswer(KEY_UNKNOWN);
    }

    function test_UnregisteredKeyRevertsOnGetValue() public {
        vm.expectRevert(abi.encodeWithSelector(IDIAAdapter.DIAFeedNotRegistered.selector, KEY_UNKNOWN));
        adapter.getValue(KEY_UNKNOWN);
    }

    function test_UnregisterFeedWorks() public {
        vm.startPrank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(oracle), DIA_KEY, MAX_STALENESS);

        vm.expectEmit(true, false, false, false);
        emit IDIAAdapter.FeedUnregistered(KEY_ETH_USD);
        adapter.unregisterFeed(KEY_ETH_USD);
        vm.stopPrank();

        (address storedOracle,,) = adapter.getFeed(KEY_ETH_USD);
        assertEq(storedOracle, address(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_InterfaceId() public pure {
        assertEq(type(IDIAAdapter).interfaceId, bytes4(0xec319d60));
    }

    function test_SupportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IDIAAdapter).interfaceId));
    }
}
