// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ITellor} from "@lattice/interfaces/external/ITellor.sol";
import {ITellorAdapter} from "@lattice/interfaces/oracles/ITellorAdapter.sol";
import {TellorAdapter} from "@lattice/oracles/TellorAdapter.sol";
import {TellorAdapterLib} from "@lattice/oracles/libraries/TellorAdapterLib.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCKS
// ---------------------------------------------------------------------------

/// @notice Minimal mock Tellor oracle with a settable `getDataBefore` response.
/// @dev `value` is `abi.encode(uint256 price)` to mirror a Tellor SpotPrice report.
contract MockTellor is ITellor {
    bool internal _found;
    bytes internal _value;
    uint256 internal _timestamp;

    function set(bool found_, bytes memory value_, uint256 timestamp_) external {
        _found = found_;
        _value = value_;
        _timestamp = timestamp_;
    }

    function setPrice(uint256 price, uint256 timestamp_) external {
        _found = true;
        _value = abi.encode(price);
        _timestamp = timestamp_;
    }

    function getDataBefore(bytes32, uint256) external view returns (bool, bytes memory, uint256) {
        return (_found, _value, _timestamp);
    }
}

/// @notice Combines AccessControl + TellorAdapter for testing.
contract MockTellorAdapterContract is AccessControl, TellorAdapter {
    function initialize(address admin, address tellor_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin);
        TellorAdapterLib.__TellorAdapter_init(tellor_);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

/// @title TellorAdapterTester
/// @notice Unit tests for the Tellor price-oracle adapter against a mock Tellor.
contract TellorAdapterTester is Test {
    MockTellorAdapterContract adapter;
    MockTellor tellor;

    address admin = address(0xA11CE);
    address user = address(0xBAD);

    bytes32 constant KEY = keccak256("ETH/USD");
    bytes32 constant KEY_UNKNOWN = keccak256("UNKNOWN");
    bytes32 constant QUERY_ID = bytes32(uint256(0xE7));

    uint48 constant DISPUTE_BUFFER = 900; // 15 minutes
    uint48 constant MAX_STALENESS = 3600; // 1 hour
    uint256 constant PRICE = 3000e18; // Tellor SpotPrice is abi.encode(uint256) at 18 decimals

    function setUp() public {
        vm.warp(1_000_000);
        tellor = new MockTellor();
        adapter = new MockTellorAdapterContract();
        adapter.initialize(admin, address(tellor));

        vm.prank(admin);
        adapter.registerFeed(KEY, QUERY_ID, DISPUTE_BUFFER, MAX_STALENESS);

        tellor.setPrice(PRICE, block.timestamp - 5);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          INITIALISATION TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_InitRevertsOnZeroTellor() public {
        MockTellorAdapterContract a = new MockTellorAdapterContract();
        vm.expectRevert(ITellorAdapter.TellorContractIsZero.selector);
        a.initialize(admin, address(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          REGISTER FEED TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegisterAndGetFeed() public view {
        (bytes32 queryId, uint48 disputeBuffer, uint48 maxStaleness) = adapter.getFeed(KEY);
        assertEq(queryId, QUERY_ID);
        assertEq(disputeBuffer, DISPUTE_BUFFER);
        assertEq(maxStaleness, MAX_STALENESS);
        assertEq(adapter.tellor(), address(tellor));
    }

    function test_RegisterFeedRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        adapter.registerFeed(KEY, QUERY_ID, DISPUTE_BUFFER, MAX_STALENESS);
    }

    function test_RegisterFeedEmitsFeedRegistered() public {
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit ITellorAdapter.FeedRegistered(KEY, QUERY_ID, DISPUTE_BUFFER, MAX_STALENESS);
        adapter.registerFeed(KEY, QUERY_ID, DISPUTE_BUFFER, MAX_STALENESS);
    }

    function test_RegisterInvalidConfigReverts() public {
        vm.startPrank(admin);
        vm.expectRevert(ITellorAdapter.TellorInvalidConfig.selector);
        adapter.registerFeed(KEY, bytes32(0), DISPUTE_BUFFER, MAX_STALENESS); // zero queryId
        vm.expectRevert(ITellorAdapter.TellorInvalidConfig.selector);
        adapter.registerFeed(KEY, QUERY_ID, DISPUTE_BUFFER, 0); // zero staleness
        vm.stopPrank();
    }

    function test_RegisterFeedZeroDisputeBufferAllowed() public {
        vm.prank(admin);
        adapter.registerFeed(KEY, QUERY_ID, 0, MAX_STALENESS);
        (, uint48 disputeBuffer,) = adapter.getFeed(KEY);
        assertEq(disputeBuffer, 0);

        // Reads still succeed with no buffer.
        tellor.setPrice(PRICE, block.timestamp - 5);
        assertEq(adapter.latestAnswer(KEY), int256(PRICE));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          LATEST ANSWER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice SpotPrice value (already 18-dec) is decoded and widened to int256.
    function test_LatestAnswerDecodesWad() public view {
        assertEq(adapter.latestAnswer(KEY), int256(PRICE));
    }

    function test_GetDataBeforeReturnsRawBytes() public view {
        (bytes memory value, uint256 timestamp) = adapter.getDataBefore(KEY);
        assertEq(abi.decode(value, (uint256)), PRICE);
        assertEq(timestamp, block.timestamp - 5);
    }

    /// @notice The dispute buffer is stored and reads succeed across a range of buffers.
    function test_DisputeBufferStoredAndReadsSucceed() public {
        vm.prank(admin);
        adapter.registerFeed(KEY, QUERY_ID, 1200, MAX_STALENESS);
        (, uint48 disputeBuffer,) = adapter.getFeed(KEY);
        assertEq(disputeBuffer, 1200);

        tellor.setPrice(PRICE, block.timestamp - 5);
        assertEq(adapter.latestAnswer(KEY), int256(PRICE));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              NO-DATA TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_NoDataWhenNotFoundReverts() public {
        tellor.set(false, abi.encode(PRICE), block.timestamp - 5);
        vm.expectRevert(abi.encodeWithSelector(ITellorAdapter.TellorNoData.selector, KEY));
        adapter.latestAnswer(KEY);
    }

    function test_NoDataWhenEmptyValueReverts() public {
        tellor.set(true, bytes(""), block.timestamp - 5);
        vm.expectRevert(abi.encodeWithSelector(ITellorAdapter.TellorNoData.selector, KEY));
        adapter.getDataBefore(KEY);
    }

    function test_NoDataWhenZeroPriceReverts() public {
        tellor.setPrice(0, block.timestamp - 5);
        vm.expectRevert(abi.encodeWithSelector(ITellorAdapter.TellorNoData.selector, KEY));
        adapter.latestAnswer(KEY);
    }

    /// @notice A reporter price >= 2^255 (which would wrap to a negative int256) is rejected as no-data.
    /// @dev `value` is permissionless reporter data, so this upper-bound guard is load-bearing.
    function test_NoDataWhenPriceOverflowsInt256() public {
        tellor.setPrice(uint256(type(int256).max) + 1, block.timestamp - 5); // 2^255
        vm.expectRevert(abi.encodeWithSelector(ITellorAdapter.TellorNoData.selector, KEY));
        adapter.latestAnswer(KEY);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            STALENESS TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_RevertsOnStaleData() public {
        uint256 staleTs = block.timestamp - MAX_STALENESS - 1;
        tellor.setPrice(PRICE, staleTs);
        vm.expectRevert(
            abi.encodeWithSelector(ITellorAdapter.TellorStaleData.selector, KEY, staleTs, uint256(MAX_STALENESS))
        );
        adapter.latestAnswer(KEY);
    }

    function test_FutureTimestampRevertsStale() public {
        uint256 futureTs = block.timestamp + 100;
        tellor.setPrice(PRICE, futureTs);
        vm.expectRevert(
            abi.encodeWithSelector(ITellorAdapter.TellorStaleData.selector, KEY, futureTs, uint256(MAX_STALENESS))
        );
        adapter.latestAnswer(KEY);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     UNREGISTERED / UNREGISTER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_UnregisteredKeyReverts() public {
        vm.expectRevert(abi.encodeWithSelector(ITellorAdapter.TellorFeedNotRegistered.selector, KEY_UNKNOWN));
        adapter.latestAnswer(KEY_UNKNOWN);
    }

    function test_UnregisterFeed() public {
        vm.startPrank(admin);
        vm.expectEmit(true, false, false, false);
        emit ITellorAdapter.FeedUnregistered(KEY);
        adapter.unregisterFeed(KEY);
        vm.stopPrank();

        (, uint48 disputeBuffer, uint48 maxStaleness) = adapter.getFeed(KEY);
        assertEq(disputeBuffer, 0);
        assertEq(maxStaleness, 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              SET TELLOR TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SetTellor() public {
        MockTellor t2 = new MockTellor();
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit ITellorAdapter.TellorContractSet(address(t2));
        adapter.setTellor(address(t2));
        assertEq(adapter.tellor(), address(t2));
    }

    function test_SetTellorOnlyAdmin() public {
        vm.prank(user);
        vm.expectRevert();
        adapter.setTellor(address(0xC0FFEE));
    }

    function test_SetTellorZeroReverts() public {
        vm.prank(admin);
        vm.expectRevert(ITellorAdapter.TellorContractIsZero.selector);
        adapter.setTellor(address(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_InterfaceIdMatchesConstant() public pure {
        assertEq(type(ITellorAdapter).interfaceId, bytes4(0xddc762ca), "ITellorAdapter interfaceId moved");
    }

    function test_SupportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(ITellorAdapter).interfaceId));
    }
}
