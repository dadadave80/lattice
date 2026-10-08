// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {OracleGuardTestBase} from "@lattice-test/base/OracleGuardTestBase.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IAggregatorV3} from "@lattice/interfaces/external/chainlink/IAggregatorV3.sol";
import {IChainlinkAdapter} from "@lattice/interfaces/oracles/IChainlinkAdapter.sol";
import {IOracleGuard} from "@lattice/interfaces/oracles/IOracleGuard.sol";

/// @notice Settable AggregatorV3 used both as a price feed and as an L2 sequencer-uptime feed.
contract MockGuardAggregator is IAggregatorV3 {
    uint8 public immutable decimals;
    string public description;

    uint80 internal _roundId;
    int256 internal _answer;
    uint256 internal _startedAt;
    uint256 internal _updatedAt;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }

    function set(int256 answer_, uint256 startedAt_, uint256 updatedAt_) external {
        ++_roundId;
        _answer = answer_;
        _startedAt = startedAt_;
        _updatedAt = updatedAt_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (_roundId, _answer, _startedAt, _updatedAt, _roundId);
    }
}

/// @title OracleGuardTest
/// @notice Exercises the OracleGuard through real diamonds: a standalone guard diamond reading a separate Chainlink
///         adapter diamond, and a co-cut diamond where the guard reads its own adapter. Mock aggregators stand in
///         for the Chainlink price feed and the L2 sequencer-uptime feed.
contract OracleGuardTest is OracleGuardTestBase {
    address internal admin = address(0xA11CE);
    address internal user = address(0xB0B);

    bytes32 internal constant KEY = keccak256("ETH/USD");
    bytes32 internal constant KEY_UNKNOWN = keccak256("UNKNOWN");
    uint48 internal constant MAX_STALENESS = 3600;
    uint48 internal constant GRACE = 3600;
    int256 internal constant PRICE_8DEC = 3000e8;
    int256 internal constant PRICE_WAD = 3000e18;

    IOracleGuard internal guard;
    IChainlinkAdapter internal adapter;
    MockGuardAggregator internal priceFeed;
    MockGuardAggregator internal sequencer;

    function setUp() public {
        vm.warp(1_000_000);

        guard = IOracleGuard(_deployOracleGuard(admin));
        adapter = IChainlinkAdapter(_deployChainlinkAdapter(admin));

        priceFeed = new MockGuardAggregator(8);
        priceFeed.set(PRICE_8DEC, block.timestamp - 10, block.timestamp - 5);
        sequencer = new MockGuardAggregator(0);
        // Up since well before the grace period.
        sequencer.set(0, block.timestamp - 2 * GRACE, block.timestamp - 2 * GRACE);

        vm.startPrank(admin);
        adapter.registerFeed(KEY, address(priceFeed), MAX_STALENESS);
        guard.setGuardedFeed(KEY, address(adapter), 0, 0);
        vm.stopPrank();
    }

    function _enableSequencer() internal {
        vm.prank(admin);
        guard.setSequencerConfig(address(sequencer), GRACE);
    }

    function _setBounds(int256 minAnswer, int256 maxAnswer) internal {
        vm.prank(admin);
        guard.setGuardedFeed(KEY, address(adapter), minAnswer, maxAnswer);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               UNSET CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice With no sequencer feed and no bounds, the guarded read equals the adapter's read.
    function test_GuardedAnswer_PassesThroughWithoutChecks() public view {
        assertEq(guard.guardedAnswer(KEY), PRICE_WAD);
        assertEq(guard.guardedAnswer(KEY), adapter.latestAnswer(KEY));
    }

    /// @notice An unconfigured key fails closed instead of passing a price through unchecked.
    function test_GuardedAnswer_RevertsForUnconfiguredKey() public {
        vm.expectRevert(abi.encodeWithSelector(IOracleGuard.OracleGuardKeyNotConfigured.selector, KEY_UNKNOWN));
        guard.guardedAnswer(KEY_UNKNOWN);
    }

    /// @notice A removed key fails closed.
    function test_RemoveGuardedFeed_RevertsAfterRemoval() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(guard));
        emit IOracleGuard.GuardedFeedRemoved(KEY);
        guard.removeGuardedFeed(KEY);

        (address oracle, int256 minAnswer, int256 maxAnswer) = guard.getGuardedFeed(KEY);
        assertEq(oracle, address(0));
        assertEq(minAnswer, 0);
        assertEq(maxAnswer, 0);
        vm.expectRevert(abi.encodeWithSelector(IOracleGuard.OracleGuardKeyNotConfigured.selector, KEY));
        guard.guardedAnswer(KEY);
    }

    /// @notice With no sequencer feed, `checkSequencerUptime` is a no-op.
    function test_CheckSequencerUptime_NoOpWhenUnset() public view {
        guard.checkSequencerUptime();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              SEQUENCER UPTIME
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice A sequencer that is up and past its grace period lets the read through.
    function test_Sequencer_UpPastGracePasses() public {
        _enableSequencer();
        guard.checkSequencerUptime();
        assertEq(guard.guardedAnswer(KEY), PRICE_WAD);
    }

    /// @notice `answer != 0` (down) reverts.
    function test_Sequencer_DownReverts() public {
        _enableSequencer();
        uint256 startedAt = block.timestamp - 2 * GRACE;
        sequencer.set(1, startedAt, startedAt);

        vm.expectRevert(abi.encodeWithSelector(IOracleGuard.OracleGuardSequencerDown.selector, int256(1), startedAt));
        guard.guardedAnswer(KEY);
        vm.expectRevert(abi.encodeWithSelector(IOracleGuard.OracleGuardSequencerDown.selector, int256(1), startedAt));
        guard.checkSequencerUptime();
    }

    /// @notice `startedAt == 0` (an uninitialized Arbitrum uptime feed) fails closed.
    function test_Sequencer_UninitializedReverts() public {
        _enableSequencer();
        sequencer.set(0, 0, 0);

        vm.expectRevert(abi.encodeWithSelector(IOracleGuard.OracleGuardSequencerDown.selector, int256(0), uint256(0)));
        guard.guardedAnswer(KEY);
    }

    /// @notice Inside the grace period (`now - startedAt == gracePeriod`) reverts; one second later passes.
    function test_Sequencer_GracePeriodBoundary() public {
        _enableSequencer();
        uint256 restartedAt = block.timestamp;
        sequencer.set(0, restartedAt, restartedAt);

        vm.expectRevert(
            abi.encodeWithSelector(IOracleGuard.OracleGuardGracePeriodNotOver.selector, restartedAt, uint256(GRACE))
        );
        guard.guardedAnswer(KEY);

        vm.warp(restartedAt + GRACE);
        priceFeed.set(PRICE_8DEC, block.timestamp, block.timestamp);
        vm.expectRevert(
            abi.encodeWithSelector(IOracleGuard.OracleGuardGracePeriodNotOver.selector, restartedAt, uint256(GRACE))
        );
        guard.guardedAnswer(KEY);

        vm.warp(restartedAt + GRACE + 1);
        assertEq(guard.guardedAnswer(KEY), PRICE_WAD);
    }

    /// @notice A `startedAt` in the future is treated as inside the grace period, not an underflow panic.
    function test_Sequencer_FutureStartedAtReverts() public {
        _enableSequencer();
        uint256 future = block.timestamp + 1;
        sequencer.set(0, future, future);

        vm.expectRevert(
            abi.encodeWithSelector(IOracleGuard.OracleGuardGracePeriodNotOver.selector, future, uint256(GRACE))
        );
        guard.guardedAnswer(KEY);
    }

    /// @notice A sequencer outage blocks reads even when the last price is still within the adapter's staleness.
    function test_Sequencer_DownBlocksFreshLookingPrice() public {
        _enableSequencer();
        sequencer.set(1, block.timestamp, block.timestamp);
        assertEq(adapter.latestAnswer(KEY), PRICE_WAD, "adapter alone accepts the pre-outage answer");

        vm.expectRevert(
            abi.encodeWithSelector(IOracleGuard.OracleGuardSequencerDown.selector, int256(1), block.timestamp)
        );
        guard.guardedAnswer(KEY);
    }

    /// @notice Clearing the sequencer feed disables the check again.
    function test_Sequencer_DisableSkipsCheck() public {
        _enableSequencer();
        sequencer.set(1, block.timestamp, block.timestamp);

        vm.prank(admin);
        guard.setSequencerConfig(address(0), 0);
        assertEq(guard.guardedAnswer(KEY), PRICE_WAD);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ADAPTER CHECKS BUBBLE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice A stale adapter answer reverts with the adapter's own error through the guard.
    function test_GuardedAnswer_BubblesAdapterStaleness() public {
        uint256 staleAt = block.timestamp - MAX_STALENESS - 1;
        priceFeed.set(PRICE_8DEC, staleAt, staleAt);

        vm.expectRevert(
            abi.encodeWithSelector(IChainlinkAdapter.ChainlinkStaleData.selector, KEY, staleAt, uint256(MAX_STALENESS))
        );
        guard.guardedAnswer(KEY);
    }

    /// @notice A Chainlink feed with more than 18 decimals whose answer truncates to zero reverts in the adapter.
    function test_GuardedAnswer_BubblesTruncatedHighDecimalAnswer() public {
        MockGuardAggregator feed20 = new MockGuardAggregator(20);
        feed20.set(99, block.timestamp - 10, block.timestamp - 5);
        bytes32 key20 = keccak256("TINY/USD");
        vm.startPrank(admin);
        adapter.registerFeed(key20, address(feed20), MAX_STALENESS);
        guard.setGuardedFeed(key20, address(adapter), 0, 0);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IChainlinkAdapter.ChainlinkInvalidAnswer.selector, key20, int256(99)));
        guard.guardedAnswer(key20);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  BOUNDS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice An answer inside `[min, max]` (inclusive) passes.
    function test_Bounds_InsideAndEdgesPass() public {
        _setBounds(PRICE_WAD, PRICE_WAD);
        assertEq(guard.guardedAnswer(KEY), PRICE_WAD);

        _setBounds(1000e18, 5000e18);
        assertEq(guard.guardedAnswer(KEY), PRICE_WAD);
    }

    /// @notice An answer below `minAnswer` reverts.
    function test_Bounds_BelowMinReverts() public {
        _setBounds(3001e18, 5000e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleGuard.OracleGuardAnswerOutOfBounds.selector, KEY, PRICE_WAD, int256(3001e18), int256(5000e18)
            )
        );
        guard.guardedAnswer(KEY);
    }

    /// @notice An answer above `maxAnswer` reverts.
    function test_Bounds_AboveMaxReverts() public {
        _setBounds(0, 2999e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleGuard.OracleGuardAnswerOutOfBounds.selector, KEY, PRICE_WAD, int256(0), int256(2999e18)
            )
        );
        guard.guardedAnswer(KEY);
    }

    /// @notice Fuzz: with bounds set, the guard returns the answer iff it lies in `[min, max]`.
    function testFuzz_Bounds(uint64 rawPrice, uint128 minAnswer, uint128 width) public {
        vm.assume(rawPrice != 0);
        int256 minA = int256(uint256(minAnswer));
        int256 maxA = minA + int256(uint256(width));
        vm.assume(maxA != 0);
        _setBounds(minA, maxA);
        priceFeed.set(int256(uint256(rawPrice)), block.timestamp - 10, block.timestamp - 5);
        int256 wad = int256(uint256(rawPrice)) * 1e10;

        if (wad < minA || wad > maxA) {
            vm.expectRevert(
                abi.encodeWithSelector(IOracleGuard.OracleGuardAnswerOutOfBounds.selector, KEY, wad, minA, maxA)
            );
            guard.guardedAnswer(KEY);
        } else {
            assertEq(guard.guardedAnswer(KEY), wad);
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           NON-POSITIVE ANSWERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice A non-positive WAD answer from any oracle reverts even with bounds disabled.
    function test_GuardedAnswer_RevertsOnNonPositiveAnswer() public {
        ZeroOracle zero = new ZeroOracle();
        vm.prank(admin);
        guard.setGuardedFeed(KEY, address(zero), 0, 0);

        vm.expectRevert(abi.encodeWithSelector(IOracleGuard.OracleGuardInvalidAnswer.selector, KEY, int256(0)));
        guard.guardedAnswer(KEY);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 CO-CUT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Cut next to the adapter, the guard reads its own diamond.
    function test_CoCut_GuardReadsOwnDiamond() public {
        address d = _deployCoCutChainlinkGuard(admin);
        assertTrue(ERC165Facet(d).supportsInterface(type(IOracleGuard).interfaceId));
        assertTrue(ERC165Facet(d).supportsInterface(type(IChainlinkAdapter).interfaceId));
        vm.startPrank(admin);
        IChainlinkAdapter(d).registerFeed(KEY, address(priceFeed), MAX_STALENESS);
        IOracleGuard(d).setGuardedFeed(KEY, d, 1000e18, 5000e18);
        IOracleGuard(d).setSequencerConfig(address(sequencer), GRACE);
        vm.stopPrank();

        assertEq(IOracleGuard(d).guardedAnswer(KEY), PRICE_WAD);

        sequencer.set(1, block.timestamp, block.timestamp);
        vm.expectRevert(
            abi.encodeWithSelector(IOracleGuard.OracleGuardSequencerDown.selector, int256(1), block.timestamp)
        );
        IOracleGuard(d).guardedAnswer(KEY);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Setters are `DEFAULT_ADMIN_ROLE`-gated.
    function test_Setters_RevertForNonAdmin() public {
        bytes memory err =
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, bytes32(0));
        vm.startPrank(user);
        vm.expectRevert(err);
        guard.setSequencerConfig(address(sequencer), GRACE);
        vm.expectRevert(err);
        guard.setGuardedFeed(KEY, address(adapter), 1, 2);
        vm.expectRevert(err);
        guard.removeGuardedFeed(KEY);
        vm.stopPrank();
    }

    /// @notice `setSequencerConfig` stores the config and emits.
    function test_SetSequencerConfig_StoresAndEmits() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(guard));
        emit IOracleGuard.SequencerConfigSet(address(sequencer), GRACE);
        guard.setSequencerConfig(address(sequencer), GRACE);

        (address feed, uint48 gracePeriod) = guard.getSequencerConfig();
        assertEq(feed, address(sequencer));
        assertEq(gracePeriod, GRACE);
    }

    /// @notice A sequencer feed with a zero grace period is rejected.
    function test_SetSequencerConfig_RevertsOnZeroGrace() public {
        vm.prank(admin);
        vm.expectRevert(IOracleGuard.OracleGuardInvalidConfig.selector);
        guard.setSequencerConfig(address(sequencer), 0);
    }

    /// @notice `setGuardedFeed` stores the config and emits.
    function test_SetGuardedFeed_StoresAndEmits() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(guard));
        emit IOracleGuard.GuardedFeedSet(KEY, address(adapter), 1000e18, 5000e18);
        guard.setGuardedFeed(KEY, address(adapter), 1000e18, 5000e18);

        (address oracle, int256 minAnswer, int256 maxAnswer) = guard.getGuardedFeed(KEY);
        assertEq(oracle, address(adapter));
        assertEq(minAnswer, 1000e18);
        assertEq(maxAnswer, 5000e18);
    }

    /// @notice `setGuardedFeed` rejects a zero oracle, a negative minimum and inverted bounds.
    function test_SetGuardedFeed_RevertsOnInvalidConfig() public {
        vm.startPrank(admin);
        vm.expectRevert(IOracleGuard.OracleGuardInvalidConfig.selector);
        guard.setGuardedFeed(KEY, address(0), 0, 0);
        vm.expectRevert(IOracleGuard.OracleGuardInvalidConfig.selector);
        guard.setGuardedFeed(KEY, address(adapter), -1, 5000e18);
        vm.expectRevert(IOracleGuard.OracleGuardInvalidConfig.selector);
        guard.setGuardedFeed(KEY, address(adapter), 5000e18, 1000e18);
        vm.stopPrank();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 ERC-165
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The recipe init registers IOracleGuard.
    function test_SupportsInterface() public view {
        assertTrue(ERC165Facet(address(guard)).supportsInterface(type(IOracleGuard).interfaceId));
        assertTrue(ERC165Facet(address(guard)).supportsInterface(type(IAccessControl).interfaceId));
    }
}

/// @notice An oracle whose WAD read truncated to zero (e.g. an adapter with more than 18 decimals).
contract ZeroOracle {
    function latestAnswer(bytes32) external pure returns (int256) {
        return 0;
    }
}
