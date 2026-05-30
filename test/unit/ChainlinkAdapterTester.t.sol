// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IChainlinkAdapter} from "@lattice/interfaces/IChainlinkAdapter.sol";
import {IAggregatorV3} from "@lattice/interfaces/external/IAggregatorV3.sol";
import {ChainlinkAdapter} from "@lattice/oracles/ChainlinkAdapter.sol";
import {ChainlinkAdapterLib} from "@lattice/oracles/libraries/ChainlinkAdapterLib.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCKS
// ---------------------------------------------------------------------------

/// @notice Minimal mock AggregatorV3 with settable fields.
contract MockAggregator is IAggregatorV3 {
    uint8 public decimals;
    string public description;

    int256 public answer;
    uint256 public updatedAt;
    uint80 public roundId;
    uint80 public answeredInRound;
    uint256 public startedAt;

    constructor(uint8 _decimals) {
        decimals = _decimals;
    }

    function setRoundData(
        uint80 _roundId,
        int256 _answer,
        uint256 _startedAt,
        uint256 _updatedAt,
        uint80 _answeredInRound
    ) external {
        roundId = _roundId;
        answer = _answer;
        startedAt = _startedAt;
        updatedAt = _updatedAt;
        answeredInRound = _answeredInRound;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}

/// @notice Combines AccessControl + ChainlinkAdapter for testing.
contract MockChainlinkAdapterContract is AccessControl, ChainlinkAdapter {
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        ChainlinkAdapterLib.__ChainlinkAdapter_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

contract ChainlinkAdapterTester is Test {
    MockChainlinkAdapterContract adapter;
    MockAggregator feed8; // 8-decimal (typical Chainlink USD feeds)
    MockAggregator feed18; // 18-decimal
    MockAggregator feed6; // 6-decimal

    address admin = address(0x1);
    address user = address(0x2);

    bytes32 constant KEY_ETH_USD = keccak256("ETH/USD");
    bytes32 constant KEY_ETH_USD_18 = keccak256("ETH/USD18");
    bytes32 constant KEY_ETH_USD_6 = keccak256("ETH/USD6");
    bytes32 constant KEY_UNKNOWN = keccak256("UNKNOWN");

    uint48 constant MAX_STALENESS = 3600; // 1 hour

    // Fresh round data values
    uint80 constant ROUND_ID = 100;
    int256 constant PRICE_8DEC = 300000000000; // 3000e8 (representing $3000)
    int256 constant PRICE_18DEC = 3000e18;
    int256 constant PRICE_6DEC = 3000e6;

    function setUp() public {
        // Start from a non-zero timestamp so subtractions don't underflow.
        vm.warp(10_000);

        adapter = new MockChainlinkAdapterContract();
        adapter.initialize(admin);

        feed8 = new MockAggregator(8);
        feed18 = new MockAggregator(18);
        feed6 = new MockAggregator(6);

        // Set up fresh round data (updatedAt a few seconds before now).
        feed8.setRoundData(ROUND_ID, PRICE_8DEC, block.timestamp - 10, block.timestamp - 5, ROUND_ID);
        feed18.setRoundData(ROUND_ID, PRICE_18DEC, block.timestamp - 10, block.timestamp - 5, ROUND_ID);
        feed6.setRoundData(ROUND_ID, PRICE_6DEC, block.timestamp - 10, block.timestamp - 5, ROUND_ID);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          REGISTER FEED TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Non-admin reverts with AccessControlUnauthorizedAccount.
    function test_RegisterFeedRevertsNonAdminWithCorrectError() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        adapter.registerFeed(KEY_ETH_USD, address(feed8), MAX_STALENESS);
    }

    /// @notice Admin can register a feed and it's stored correctly.
    function test_RegisterFeedByAdmin() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(feed8), MAX_STALENESS);

        (address storedFeed, uint48 storedStaleness) = adapter.getFeed(KEY_ETH_USD);
        assertEq(storedFeed, address(feed8));
        assertEq(storedStaleness, MAX_STALENESS);
    }

    /// @notice Registering a feed emits FeedRegistered event.
    function test_RegisterFeedEmitsFeedRegistered() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IChainlinkAdapter.FeedRegistered(KEY_ETH_USD, address(feed8), MAX_STALENESS);
        adapter.registerFeed(KEY_ETH_USD, address(feed8), MAX_STALENESS);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          LATEST ANSWER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice 8-decimal feed returns WAD-normalised answer.
    function test_LatestAnswer8DecimalNormalized() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(feed8), MAX_STALENESS);

        int256 wad = adapter.latestAnswer(KEY_ETH_USD);
        // 300000000000 (3000e8) * 10^(18-8) = 3000e18
        assertEq(wad, 3000e18);
    }

    /// @notice 18-decimal feed returns answer unchanged.
    function test_LatestAnswer18DecimalUnchanged() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD_18, address(feed18), MAX_STALENESS);

        int256 wad = adapter.latestAnswer(KEY_ETH_USD_18);
        assertEq(wad, PRICE_18DEC);
    }

    /// @notice 6-decimal feed returns WAD-normalised answer.
    function test_LatestAnswer6DecimalNormalized() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD_6, address(feed6), MAX_STALENESS);

        int256 wad = adapter.latestAnswer(KEY_ETH_USD_6);
        // 3000e6 * 10^(18-6) = 3000e18
        assertEq(wad, 3000e18);
    }

    /// @notice latestAnswerRaw returns the raw fields.
    function test_LatestAnswerRawReturnsFeedData() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(feed8), MAX_STALENESS);

        (int256 rawAnswer, uint256 updatedAt, uint8 decimals_) = adapter.latestAnswerRaw(KEY_ETH_USD);
        assertEq(rawAnswer, PRICE_8DEC);
        assertEq(decimals_, 8);
        assertTrue(updatedAt > 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            STALENESS TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Stale data past threshold reverts.
    function test_LatestAnswerRevertsOnStaleData() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(feed8), MAX_STALENESS);

        // Warp time so data is older than maxStaleness
        uint256 staleUpdatedAt = block.timestamp - MAX_STALENESS - 1;
        feed8.setRoundData(ROUND_ID, PRICE_8DEC, staleUpdatedAt - 10, staleUpdatedAt, ROUND_ID);
        vm.warp(block.timestamp + MAX_STALENESS + 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                IChainlinkAdapter.ChainlinkStaleData.selector, KEY_ETH_USD, staleUpdatedAt, MAX_STALENESS
            )
        );
        adapter.latestAnswer(KEY_ETH_USD);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           INVALID ANSWER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Negative answer reverts with ChainlinkInvalidAnswer.
    function test_NegativeAnswerReverts() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(feed8), MAX_STALENESS);

        feed8.setRoundData(ROUND_ID, -1, block.timestamp - 10, block.timestamp - 5, ROUND_ID);

        vm.expectRevert(
            abi.encodeWithSelector(IChainlinkAdapter.ChainlinkInvalidAnswer.selector, KEY_ETH_USD, int256(-1))
        );
        adapter.latestAnswer(KEY_ETH_USD);
    }

    /// @notice Zero answer reverts with ChainlinkInvalidAnswer.
    function test_ZeroAnswerReverts() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(feed8), MAX_STALENESS);

        feed8.setRoundData(ROUND_ID, 0, block.timestamp - 10, block.timestamp - 5, ROUND_ID);

        vm.expectRevert(
            abi.encodeWithSelector(IChainlinkAdapter.ChainlinkInvalidAnswer.selector, KEY_ETH_USD, int256(0))
        );
        adapter.latestAnswer(KEY_ETH_USD);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          INCOMPLETE ROUND TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Zero updatedAt reverts with ChainlinkRoundIncomplete.
    function test_ZeroUpdatedAtReverts() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(feed8), MAX_STALENESS);

        feed8.setRoundData(ROUND_ID, PRICE_8DEC, 0, 0, ROUND_ID);

        vm.expectRevert(abi.encodeWithSelector(IChainlinkAdapter.ChainlinkRoundIncomplete.selector, KEY_ETH_USD));
        adapter.latestAnswer(KEY_ETH_USD);
    }

    /// @notice answeredInRound < roundId reverts with ChainlinkRoundIncomplete.
    function test_AnsweredInRoundLessThanRoundIdReverts() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(feed8), MAX_STALENESS);

        // answeredInRound (99) < roundId (100)
        feed8.setRoundData(ROUND_ID, PRICE_8DEC, block.timestamp - 10, block.timestamp - 5, ROUND_ID - 1);

        vm.expectRevert(abi.encodeWithSelector(IChainlinkAdapter.ChainlinkRoundIncomplete.selector, KEY_ETH_USD));
        adapter.latestAnswer(KEY_ETH_USD);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          UNREGISTER FEED TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Unregistering a feed removes it from storage and emits event.
    function test_UnregisterFeedWorks() public {
        vm.startPrank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(feed8), MAX_STALENESS);

        vm.expectEmit(true, false, false, false);
        emit IChainlinkAdapter.FeedUnregistered(KEY_ETH_USD);
        adapter.unregisterFeed(KEY_ETH_USD);
        vm.stopPrank();

        (address storedFeed,) = adapter.getFeed(KEY_ETH_USD);
        assertEq(storedFeed, address(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         UNREGISTERED KEY TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Querying an unregistered key reverts with ChainlinkFeedNotRegistered.
    function test_UnregisteredKeyRevertsOnLatestAnswer() public {
        vm.expectRevert(abi.encodeWithSelector(IChainlinkAdapter.ChainlinkFeedNotRegistered.selector, KEY_UNKNOWN));
        adapter.latestAnswer(KEY_UNKNOWN);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                   FUTURE TIMESTAMP TESTS (T4 / M3)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice A feed that returns updatedAt > block.timestamp reverts ChainlinkStaleData
    ///         (not an arithmetic underflow panic).
    function test_FutureUpdatedAtRevertsChainlinkStaleData() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, address(feed8), MAX_STALENESS);

        // Set updatedAt to a future timestamp (100 seconds ahead).
        uint256 futureTime = block.timestamp + 100;
        feed8.setRoundData(ROUND_ID, PRICE_8DEC, futureTime - 10, futureTime, ROUND_ID);

        vm.expectRevert(
            abi.encodeWithSelector(
                IChainlinkAdapter.ChainlinkStaleData.selector, KEY_ETH_USD, futureTime, MAX_STALENESS
            )
        );
        adapter.latestAnswer(KEY_ETH_USD);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                   REGISTER FEED CUSTOM ERROR TESTS (M4)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice registerFeed with zero feed address reverts ChainlinkFeedNotRegistered.
    function test_RegisterFeedRevertsOnZeroFeedAddress() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IChainlinkAdapter.ChainlinkFeedNotRegistered.selector, KEY_ETH_USD));
        adapter.registerFeed(KEY_ETH_USD, address(0), MAX_STALENESS);
    }

    /// @notice registerFeed with zero maxStaleness reverts ChainlinkInvalidConfig.
    function test_RegisterFeedRevertsOnZeroMaxStaleness() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IChainlinkAdapter.ChainlinkInvalidConfig.selector));
        adapter.registerFeed(KEY_ETH_USD, address(feed8), 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                   18-DECIMAL NO-NORMALIZATION TEST
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice A feed with exactly 18 decimals returns the raw answer without scaling.
    function test_LatestAnswer18DecimalNoNormalization() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD_18, address(feed18), MAX_STALENESS);

        int256 wad = adapter.latestAnswer(KEY_ETH_USD_18);
        // No up-scaling or down-scaling should occur: answer == answerWad.
        assertEq(wad, PRICE_18DEC, "18-decimal feed should return raw answer unchanged");

        // Verify via raw values as well.
        (int256 rawAnswer,, uint8 dec) = adapter.latestAnswerRaw(KEY_ETH_USD_18);
        assertEq(rawAnswer, PRICE_18DEC);
        assertEq(dec, 18);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice supportsInterface returns true for IChainlinkAdapter after init.
    function test_SupportsInterfaceChainlinkAdapter() public view {
        assertTrue(adapter.supportsInterface(type(IChainlinkAdapter).interfaceId));
    }
}
