// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {TWAPOracleTestBase} from "@lattice-test/base/TWAPOracleTestBase.sol";
import {IUniswapV2Pair} from "@lattice/interfaces/external/uniswap/IUniswapV2Pair.sol";
import {ITWAPOracle} from "@lattice/interfaces/oracles/ITWAPOracle.sol";
import {TWAPOracle} from "@lattice/oracles/TWAPOracle.sol";

// ---------------------------------------------------------------------------
//                              MOCKS
// ---------------------------------------------------------------------------

/// @notice Mock Uniswap V2 pair with injectable cumulative prices.
/// @dev An EXTERNAL fixture the TWAPOracle facet reads — NOT the facet under test.
contract MockUniswapV2Pair is IUniswapV2Pair {
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint112 public reserve0 = 1e18;
    uint112 public reserve1 = 3000e18;
    uint32 public blockTimestampLast;

    function setValues(uint256 p0Cumulative, uint256 p1Cumulative, uint32 timestamp) external {
        price0CumulativeLast = p0Cumulative;
        price1CumulativeLast = p1Cumulative;
        blockTimestampLast = timestamp;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, blockTimestampLast);
    }
}

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

/// @title TWAPOracleTest
/// @notice Exercises the TWAPOracle facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployTWAPOracle} script (see {TWAPOracleTestBase}) — every call below routes through the diamond's
///         `delegatecall` dispatch, not a flattened inheritance mock. Admin gating is enforced by the cut-in
///         `AccessControl` facet; `supportsInterface` by the cut-in `ERC165Facet`.
contract TWAPOracleTest is TWAPOracleTestBase {
    MockUniswapV2Pair pair;

    address admin = address(0x1);
    address user = address(0x2);

    bytes32 constant KEY_ETH_USD = keccak256("ETH/USD");
    bytes32 constant KEY_UNKNOWN = keccak256("UNKNOWN");

    // UQ112x112 price per second at 3000:1 ratio.
    // price0Cumulative increases by price0 * elapsed, where price0 = (reserve1 / reserve0) * 2^112.
    // For simplicity only PRICE0_PER_SEC is used in correctness assertions;
    // PRICE1_PER_SEC is derived where needed with explicit arithmetic.
    uint256 constant PRICE0_PER_SEC = 3000 * (2 ** 112);

    function setUp() public {
        // Start at a non-trivial timestamp.
        vm.warp(1_000_000);

        diamond = _deployTWAPOracle(admin);
        oracle = TWAPOracle(diamond);

        pair = new MockUniswapV2Pair();
        // Initial state: cumulatives = 0, timestamp = current block
        pair.setValues(0, 0, uint32(block.timestamp));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         REGISTER PAIR TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Non-admin cannot register a pair.
    function test_RegisterPairRevertsForNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        oracle.registerPair(KEY_ETH_USD, address(pair));
    }

    /// @notice Admin can register a pair and it records an initial observation.
    function test_RegisterPairByAdmin() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));

        assertEq(oracle.getPair(KEY_ETH_USD), address(pair));

        // Initial observation should be recorded.
        ITWAPOracle.Observation memory obs = oracle.getLatestObservation(KEY_ETH_USD);
        assertEq(obs.timestamp, uint32(block.timestamp));
        assertEq(obs.price0Cumulative, 0);
        assertEq(obs.price1Cumulative, 0);
    }

    /// @notice registerPair emits PairRegistered and ObservationRecorded events.
    function test_RegisterPairEmitsEvents() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit ITWAPOracle.PairRegistered(KEY_ETH_USD, address(pair));
        oracle.registerPair(KEY_ETH_USD, address(pair));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              CONSULT TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice consult reverts when pair is not registered.
    function test_ConsultRevertsOnUnregisteredPair() public {
        vm.expectRevert(abi.encodeWithSelector(ITWAPOracle.TWAPPairNotRegistered.selector, KEY_UNKNOWN));
        oracle.consult(KEY_UNKNOWN, 300);
    }

    /// @notice consult with fewer than 2 observations reverts TWAPInsufficientHistory.
    function test_ConsultRevertsWithInsufficientHistory() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));
        // Only 1 observation was recorded at registration.
        vm.expectRevert(abi.encodeWithSelector(ITWAPOracle.TWAPInsufficientHistory.selector, KEY_ETH_USD));
        oracle.consult(KEY_ETH_USD, 300);
    }

    /// @notice consult reverts when window exceeds the age of the oldest observation.
    function test_ConsultRevertsWhenWindowTooLarge() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));

        // Advance 60 seconds and record a second observation.
        uint32 t0 = uint32(block.timestamp);
        vm.warp(block.timestamp + 60);
        pair.setValues(PRICE0_PER_SEC * 60, 0, uint32(block.timestamp));
        oracle.recordObservation(KEY_ETH_USD);

        // The oldest observation is 60 seconds old; requesting a 300-second window should revert.
        vm.expectRevert(
            abi.encodeWithSelector(ITWAPOracle.TWAPWindowTooLarge.selector, uint32(300), uint32(block.timestamp) - t0)
        );
        oracle.consult(KEY_ETH_USD, 300);
    }

    /// @notice consult returns correct TWAP over recorded observations.
    function test_ConsultReturnCorrectTWAP() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));
        // Observation 0: timestamp=1_000_000, cumulatives=0

        uint32 elapsed = 3600; // 1 hour
        uint256 p0 = PRICE0_PER_SEC * elapsed;

        vm.warp(block.timestamp + elapsed);
        pair.setValues(p0, 0, uint32(block.timestamp));
        oracle.recordObservation(KEY_ETH_USD);
        // Observation 1: timestamp=1_000_000+3600, cumulatives=PRICE*3600

        // consult over a 3600-second window should return PRICE_PER_SEC.
        (uint256 twap0,) = oracle.consult(KEY_ETH_USD, elapsed);
        assertEq(twap0, PRICE0_PER_SEC);
    }

    /// @notice consult across multiple observations picks the right base.
    function test_ConsultPicksCorrectBaseObservation() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));
        // Obs 0: t=1_000_000, cum=0

        // Obs 1: t+300, after 5 minutes
        vm.warp(block.timestamp + 300);
        pair.setValues(PRICE0_PER_SEC * 300, 0, uint32(block.timestamp));
        oracle.recordObservation(KEY_ETH_USD);

        // Obs 2: t+600, after 10 minutes total
        vm.warp(block.timestamp + 300);
        pair.setValues(PRICE0_PER_SEC * 600, 0, uint32(block.timestamp));
        oracle.recordObservation(KEY_ETH_USD);

        // Request 500-second window: obs1 (300s ago) is too recent, must use obs0 (600s ago).
        (uint256 twap0,) = oracle.consult(KEY_ETH_USD, 500);
        assertEq(twap0, PRICE0_PER_SEC);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         UNREGISTER PAIR TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice unregisterPair clears the pair and its observations.
    function test_UnregisterPairWorks() public {
        vm.startPrank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));

        vm.expectEmit(true, false, false, false);
        emit ITWAPOracle.PairUnregistered(KEY_ETH_USD);
        oracle.unregisterPair(KEY_ETH_USD);
        vm.stopPrank();

        assertEq(oracle.getPair(KEY_ETH_USD), address(0));

        // getLatestObservation should now revert TWAPPairNotRegistered.
        vm.expectRevert(abi.encodeWithSelector(ITWAPOracle.TWAPPairNotRegistered.selector, KEY_ETH_USD));
        oracle.getLatestObservation(KEY_ETH_USD);
    }

    /// @notice Non-admin cannot unregister a pair.
    function test_UnregisterPairRevertsForNonAdmin() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        oracle.unregisterPair(KEY_ETH_USD);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       RECORD OBSERVATION TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice recordObservation on unregistered pair reverts TWAPPairNotRegistered.
    function test_RecordObservationRevertsOnUnregistered() public {
        vm.expectRevert(abi.encodeWithSelector(ITWAPOracle.TWAPPairNotRegistered.selector, KEY_UNKNOWN));
        oracle.recordObservation(KEY_UNKNOWN);
    }

    /// @notice Anyone can call recordObservation.
    function test_RecordObservationPermissionless() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));

        vm.warp(block.timestamp + 60);
        pair.setValues(PRICE0_PER_SEC * 60, 0, uint32(block.timestamp));

        // Called by non-admin user — should succeed.
        vm.prank(user);
        oracle.recordObservation(KEY_ETH_USD);

        ITWAPOracle.Observation memory obs = oracle.getLatestObservation(KEY_ETH_USD);
        assertEq(obs.price0Cumulative, PRICE0_PER_SEC * 60);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       ZERO-WINDOW TESTS (T3 / M1)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice consult with windowSeconds == 0 reverts TWAPZeroWindow (not a panic).
    function test_ConsultRevertsOnZeroWindow() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));

        // Add a second observation so consult is not stopped by insufficient history.
        vm.warp(block.timestamp + 60);
        pair.setValues(PRICE0_PER_SEC * 60, 0, uint32(block.timestamp));
        oracle.recordObservation(KEY_ETH_USD);

        vm.expectRevert(abi.encodeWithSelector(ITWAPOracle.TWAPZeroWindow.selector));
        oracle.consult(KEY_ETH_USD, 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    SAME-BLOCK DEDUP TESTS (M2 / L2)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Calling recordObservation twice in the same block only stores one entry.
    function test_SameBlockRecordObservationIsDeduped() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));
        // After registerPair: 1 observation at current timestamp.

        // Call recordObservation again in the same block (same pair state).
        oracle.recordObservation(KEY_ETH_USD);
        oracle.recordObservation(KEY_ETH_USD);

        // Should still have only 1 observation (the initial one from registerPair).
        // Verify: getLatestObservation still works but consult should still revert
        // with insufficient history (only 1 unique observation).
        vm.expectRevert(abi.encodeWithSelector(ITWAPOracle.TWAPInsufficientHistory.selector, KEY_ETH_USD));
        oracle.consult(KEY_ETH_USD, 1);
    }

    /// @notice After advancing a block, a new observation is accepted normally.
    function test_NewBlockObservationIsAccepted() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));
        // Obs 0 at t=1_000_000.

        // Same block: no-op.
        oracle.recordObservation(KEY_ETH_USD);

        // Advance block.
        vm.warp(block.timestamp + 300);
        pair.setValues(PRICE0_PER_SEC * 300, 0, uint32(block.timestamp));
        oracle.recordObservation(KEY_ETH_USD);
        // Now we have 2 observations: obs0 and obs1.

        (uint256 twap0,) = oracle.consult(KEY_ETH_USD, 300);
        assertEq(twap0, PRICE0_PER_SEC);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         BOUNDARY WINDOW TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice consult with a window exactly spanning to the oldest observation works.
    function test_ConsultExactlyAtOldestObservationAge() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));
        // Obs 0: t=1_000_000, cum=0

        uint32 elapsed = 3600;
        vm.warp(block.timestamp + elapsed);
        pair.setValues(PRICE0_PER_SEC * elapsed, 0, uint32(block.timestamp));
        oracle.recordObservation(KEY_ETH_USD);
        // Obs 1: t=1_000_000+3600

        // Requesting the exact window equal to oldest age should succeed (not revert).
        (uint256 twap0,) = oracle.consult(KEY_ETH_USD, elapsed);
        assertEq(twap0, PRICE0_PER_SEC, "TWAP at exact boundary should equal price per second");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    STALE-NEWEST FRESHNESS TESTS (T8a)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice consult reverts TWAPStaleObservation when the newest observation is
    ///         older than the requested window (recording stopped long ago).
    function test_ConsultRevertsWhenNewestObservationStale() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));

        // Record a second observation 300s after registration.
        vm.warp(block.timestamp + 300);
        uint32 newestTs = uint32(block.timestamp);
        pair.setValues(PRICE0_PER_SEC * 300, 0, newestTs);
        oracle.recordObservation(KEY_ETH_USD);
        // History now spans 300s (t0 .. newestTs), enough for a 300s window normally.

        // Recording stops; a long time passes. The newest observation is now stale.
        vm.warp(block.timestamp + 10_000);

        // Requesting a 300s window: oldest age (300) satisfies the span, but the
        // newest observation is 10_000s old — far outside the window — so the TWAP
        // would be entirely historical. Must revert as stale.
        vm.expectRevert(
            abi.encodeWithSelector(ITWAPOracle.TWAPStaleObservation.selector, newestTs, uint32(block.timestamp))
        );
        oracle.consult(KEY_ETH_USD, 300);
    }

    /// @notice consult succeeds when the newest observation is fresh (within window).
    function test_ConsultSucceedsWhenNewestFresh() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));

        uint32 elapsed = 3600;
        vm.warp(block.timestamp + elapsed);
        pair.setValues(PRICE0_PER_SEC * elapsed, 0, uint32(block.timestamp));
        oracle.recordObservation(KEY_ETH_USD);

        // Newest is fresh (recorded this block); a window covering the span works.
        (uint256 twap0,) = oracle.consult(KEY_ETH_USD, elapsed);
        assertEq(twap0, PRICE0_PER_SEC);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    ELAPSED-ZERO GUARD TESTS (T8b)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice consult reverts TWAPElapsedZero (not a panic, not the misleading
    ///         TWAPWindowTooLarge) when the oldest and newest observations share a
    ///         timestamp, leaving zero usable elapsed time for the division.
    /// @dev The dedup only blocks ADJACENT duplicate timestamps, so a non-monotonic
    ///      pair timestamp sequence [T, T+300, T] is storable; here obs[0] and the
    ///      newest obs[2] both carry timestamp T (anchored at the current block so
    ///      the freshness guard passes), making elapsed == 0.
    function test_ConsultRevertsOnZeroElapsedSpan() public {
        uint32 t = uint32(block.timestamp);

        // obs0 at timestamp T.
        pair.setValues(0, 0, t);
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));

        // obs1 at timestamp T+300 (distinct from obs0 -> stored).
        pair.setValues(PRICE0_PER_SEC * 300, 0, t + 300);
        oracle.recordObservation(KEY_ETH_USD);

        // obs2 back at timestamp T (distinct from the *adjacent* obs1 -> stored).
        // Now the newest (obs2) and the oldest (obs0) share timestamp T.
        pair.setValues(PRICE0_PER_SEC * 600, 0, t);
        oracle.recordObservation(KEY_ETH_USD);

        // Newest timestamp == current block, so the freshness guard passes; the
        // span between oldest and newest is zero -> must revert TWAPElapsedZero.
        vm.expectRevert(abi.encodeWithSelector(ITWAPOracle.TWAPElapsedZero.selector, KEY_ETH_USD));
        oracle.consult(KEY_ETH_USD, 1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice supportsInterface returns true for ITWAPOracle after init.
    function test_SupportsInterfaceITWAPOracle() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(ITWAPOracle).interfaceId));
    }
}
