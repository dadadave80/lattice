// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IStdReference} from "@lattice/interfaces/external/IStdReference.sol";
import {IBandAdapter} from "@lattice/interfaces/oracles/IBandAdapter.sol";
import {BandAdapter} from "@lattice/oracles/BandAdapter.sol";
import {BandAdapterLib} from "@lattice/oracles/libraries/BandAdapterLib.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCKS
// ---------------------------------------------------------------------------

/// @notice Minimal mock Band StdReference with a settable rate + two update timestamps.
contract MockStdReference is IStdReference {
    uint256 public rate;
    uint256 public lastUpdatedBase;
    uint256 public lastUpdatedQuote;

    function set(uint256 _rate, uint256 _lastUpdatedBase, uint256 _lastUpdatedQuote) external {
        rate = _rate;
        lastUpdatedBase = _lastUpdatedBase;
        lastUpdatedQuote = _lastUpdatedQuote;
    }

    function getReferenceData(string memory, string memory) external view returns (ReferenceData memory) {
        return ReferenceData({rate: rate, lastUpdatedBase: lastUpdatedBase, lastUpdatedQuote: lastUpdatedQuote});
    }
}

/// @notice Combines AccessControl + BandAdapter for testing.
contract MockBandAdapterContract is AccessControl, BandAdapter {
    function initialize(address admin, address reference_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin);
        BandAdapterLib.__BandAdapter_init(reference_);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

/// @title BandAdapterTest
/// @notice Unit tests for the Band price-oracle adapter against a mock StdReference.
contract BandAdapterTest is Test {
    MockBandAdapterContract adapter;
    MockStdReference stdRef;

    address admin = address(0xA11CE);
    address user = address(0xBAD);

    bytes32 constant KEY_ETH_USD = keccak256("ETH/USD");
    bytes32 constant KEY_UNKNOWN = keccak256("UNKNOWN");

    string constant BASE = "ETH";
    string constant QUOTE = "USD";

    uint48 constant MAX_STALENESS = 3600; // 1 hour
    uint256 constant RATE = 3000e18; // Band rates are already 18-decimals

    function setUp() public {
        vm.warp(1_000_000);
        stdRef = new MockStdReference();
        adapter = new MockBandAdapterContract();
        adapter.initialize(admin, address(stdRef));

        stdRef.set(RATE, block.timestamp - 5, block.timestamp - 5);
    }

    function _registerEthUsd() internal {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, BASE, QUOTE, MAX_STALENESS);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    function test_InitRevertsOnZeroReference() public {
        MockBandAdapterContract a = new MockBandAdapterContract();
        vm.expectRevert(IBandAdapter.BandReferenceIsZero.selector);
        a.initialize(admin, address(0));
    }

    function test_ReferenceSetOnInit() public view {
        assertEq(adapter.stdReference(), address(stdRef));
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
        adapter.registerFeed(KEY_ETH_USD, BASE, QUOTE, MAX_STALENESS);
    }

    function test_RegisterFeedByAdmin() public {
        _registerEthUsd();

        (string memory base, string memory quote, uint48 staleness) = adapter.getFeed(KEY_ETH_USD);
        assertEq(base, BASE);
        assertEq(quote, QUOTE);
        assertEq(staleness, MAX_STALENESS);
    }

    function test_RegisterFeedEmitsFeedRegistered() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IBandAdapter.FeedRegistered(KEY_ETH_USD, BASE, QUOTE, MAX_STALENESS);
        adapter.registerFeed(KEY_ETH_USD, BASE, QUOTE, MAX_STALENESS);
    }

    function test_RegisterFeedRevertsOnEmptyBase() public {
        vm.prank(admin);
        vm.expectRevert(IBandAdapter.BandInvalidConfig.selector);
        adapter.registerFeed(KEY_ETH_USD, "", QUOTE, MAX_STALENESS);
    }

    function test_RegisterFeedRevertsOnEmptyQuote() public {
        vm.prank(admin);
        vm.expectRevert(IBandAdapter.BandInvalidConfig.selector);
        adapter.registerFeed(KEY_ETH_USD, BASE, "", MAX_STALENESS);
    }

    function test_RegisterFeedRevertsOnZeroMaxStaleness() public {
        vm.prank(admin);
        vm.expectRevert(IBandAdapter.BandInvalidConfig.selector);
        adapter.registerFeed(KEY_ETH_USD, BASE, QUOTE, 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          LATEST ANSWER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Band rate (already 18-dec) is returned unchanged, only widened.
    function test_LatestAnswerAlreadyWad() public {
        _registerEthUsd();
        assertEq(adapter.latestAnswer(KEY_ETH_USD), int256(RATE));
    }

    function test_GetReferenceDataReturnsNativeFields() public {
        _registerEthUsd();

        (uint256 rate, uint256 lastUpdatedBase, uint256 lastUpdatedQuote) = adapter.getReferenceData(KEY_ETH_USD);
        assertEq(rate, RATE);
        assertEq(lastUpdatedBase, block.timestamp - 5);
        assertEq(lastUpdatedQuote, block.timestamp - 5);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            STALENESS TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_RevertsOnStaleBase() public {
        _registerEthUsd();

        uint256 staleTs = block.timestamp - MAX_STALENESS - 1;
        stdRef.set(RATE, staleTs, block.timestamp - 5);

        vm.expectRevert(
            abi.encodeWithSelector(IBandAdapter.BandStaleData.selector, KEY_ETH_USD, staleTs, MAX_STALENESS)
        );
        adapter.latestAnswer(KEY_ETH_USD);
    }

    function test_RevertsOnStaleQuote() public {
        _registerEthUsd();

        uint256 staleTs = block.timestamp - MAX_STALENESS - 1;
        stdRef.set(RATE, block.timestamp - 5, staleTs);

        vm.expectRevert(
            abi.encodeWithSelector(IBandAdapter.BandStaleData.selector, KEY_ETH_USD, staleTs, MAX_STALENESS)
        );
        adapter.latestAnswer(KEY_ETH_USD);
    }

    function test_FutureTimestampRevertsStale() public {
        _registerEthUsd();

        uint256 futureTs = block.timestamp + 100;
        stdRef.set(RATE, futureTs, futureTs);

        vm.expectRevert(
            abi.encodeWithSelector(IBandAdapter.BandStaleData.selector, KEY_ETH_USD, futureTs, MAX_STALENESS)
        );
        adapter.latestAnswer(KEY_ETH_USD);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           INVALID ANSWER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_OverflowRateReverts() public {
        _registerEthUsd();
        uint256 huge = uint256(type(int256).max) + 1; // 2^255 wraps to negative on int256 cast
        stdRef.set(huge, block.timestamp - 5, block.timestamp - 5);

        vm.expectRevert(abi.encodeWithSelector(IBandAdapter.BandInvalidAnswer.selector, KEY_ETH_USD, huge));
        adapter.latestAnswer(KEY_ETH_USD);
    }

    function test_ZeroRateReverts() public {
        _registerEthUsd();
        stdRef.set(0, block.timestamp - 5, block.timestamp - 5);

        vm.expectRevert(abi.encodeWithSelector(IBandAdapter.BandInvalidAnswer.selector, KEY_ETH_USD, uint256(0)));
        adapter.latestAnswer(KEY_ETH_USD);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     UNREGISTERED / UNREGISTER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_UnregisteredKeyReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IBandAdapter.BandFeedNotRegistered.selector, KEY_UNKNOWN));
        adapter.latestAnswer(KEY_UNKNOWN);
    }

    function test_UnregisterFeedWorks() public {
        vm.startPrank(admin);
        adapter.registerFeed(KEY_ETH_USD, BASE, QUOTE, MAX_STALENESS);

        vm.expectEmit(true, false, false, false);
        emit IBandAdapter.FeedUnregistered(KEY_ETH_USD);
        adapter.unregisterFeed(KEY_ETH_USD);
        vm.stopPrank();

        (,, uint48 staleness) = adapter.getFeed(KEY_ETH_USD);
        assertEq(staleness, 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          SET REFERENCE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SetReference() public {
        MockStdReference r2 = new MockStdReference();
        vm.prank(admin);
        adapter.setReference(address(r2));
        assertEq(adapter.stdReference(), address(r2));
    }

    function test_SetReferenceOnlyAdmin() public {
        vm.prank(user);
        vm.expectRevert();
        adapter.setReference(address(0xC0FFEE));
    }

    function test_SetReferenceZeroReverts() public {
        vm.prank(admin);
        vm.expectRevert(IBandAdapter.BandReferenceIsZero.selector);
        adapter.setReference(address(0));
    }

    function test_SetReferenceEmitsEvent() public {
        MockStdReference r2 = new MockStdReference();
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit IBandAdapter.ReferenceSet(address(r2));
        adapter.setReference(address(r2));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_InterfaceId() public pure {
        assertEq(type(IBandAdapter).interfaceId, bytes4(0xebdf87c5), "IBandAdapter interfaceId moved");
    }

    function test_SupportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IBandAdapter).interfaceId));
    }
}
