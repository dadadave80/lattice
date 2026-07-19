// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ITWAPOracle} from "@lattice/interfaces/oracles/ITWAPOracle.sol";
import {TWAPOracle} from "@lattice/oracles/uniswap/TWAPOracle.sol";
import {TWAPOracleLib} from "@lattice/oracles/uniswap/TWAPOracleLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCK CONTRACT
// ---------------------------------------------------------------------------

/// @notice Mock Diamond that combines AccessControl + TWAPOracle, matching
///         the pattern from TWAPOracleTest.t.sol.
contract MockTWAPOracleForkContract is AccessControl, TWAPOracle {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(AccessControl, TWAPOracle) returns (bytes memory) {}

    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        s = InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        TWAPOracleLib.__TWAPOracle_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

// ---------------------------------------------------------------------------
//                              FORK TESTS
// ---------------------------------------------------------------------------

/// @title TWAPOracleFork
/// @notice Fork tests that exercise TWAPOracle against the real Uniswap V2
///         WETH/USDC pair on Ethereum mainnet.
///
/// ## vm.warp limitation on forks
/// On a forked network, `vm.warp` advances the EVM's local `block.timestamp`
/// but the Uniswap V2 pair's `price0CumulativeLast` and `blockTimestampLast`
/// are frozen at the fork block.  The pair's internal `_update()` runs only
/// on real swaps, so cumulative prices cannot advance without a live swap.
/// This means a traditional "warp + record a second observation with different
/// cumulatives" test is not possible in a pure fork test.
///
/// The tests below therefore:
///   1. Verify that pair registration works and the initial observation is
///      captured from on-chain state.
///   2. Demonstrate the TWAPInsufficientHistory revert when only one observation
///      exists (no second observation has been recorded).
///   3. Skip the 30-minute TWAP window test (documented TODO below) and instead
///      verify that consult over a zero-elapsed elapsed window is correctly
///      guarded.
///
/// TODO: A full TWAP window test requires either (a) running against a live RPC
///       with `--fork-block-number` unset (non-deterministic) or (b) directly
///       poking the pair's storage with `vm.store` to advance cumulatives.
///
/// Enabling fork tests:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   forge test --match-path "test/fork/*"
///
/// Without MAINNET_RPC_URL set, all tests in this contract are skipped.
contract TWAPOracleFork is Test {
    // -------------------------------------------------------------------------
    //                         Mainnet addresses
    // -------------------------------------------------------------------------

    /// @notice Pinned mainnet block for deterministic results (December 2024).
    uint256 constant FORK_BLOCK = 21_500_000;

    /// @notice Real Uniswap V2 WETH/USDC pair.
    address constant UNIV2_WETH_USDC = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;

    bytes32 constant KEY_WETH_USDC = keccak256("WETH/USDC");
    bytes32 constant KEY_UNKNOWN = keccak256("UNKNOWN");

    // -------------------------------------------------------------------------
    //                              State
    // -------------------------------------------------------------------------

    MockTWAPOracleForkContract oracle;
    address admin = address(0x1);

    // -------------------------------------------------------------------------
    //                              Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", FORK_BLOCK);

        oracle = new MockTWAPOracleForkContract();
        oracle.initialize(admin);
    }

    // -------------------------------------------------------------------------
    //                              Tests
    // -------------------------------------------------------------------------

    /// @notice Register the real WETH/USDC pair; recordObservation should capture
    ///         the live cumulative prices and getLatestObservation should return them.
    function test_Fork_RegisterWETHUSDCPairAndRecordObservation() public {
        vm.prank(admin);
        oracle.registerPair(KEY_WETH_USDC, UNIV2_WETH_USDC);

        assertEq(oracle.getPair(KEY_WETH_USDC), UNIV2_WETH_USDC, "pair address mismatch");

        ITWAPOracle.Observation memory obs = oracle.getLatestObservation(KEY_WETH_USDC);

        // The pair has been active since 2020; cumulatives must be large non-zero
        // values.  The exact values depend on the forked block.
        assertTrue(obs.price0Cumulative > 0, "price0Cumulative should be non-zero");
        assertTrue(obs.price1Cumulative > 0, "price1Cumulative should be non-zero");
        assertTrue(obs.timestamp > 0, "timestamp should be non-zero");

        // Record a second observation immediately (same block = same cumulatives).
        // This exercises the path but won't advance the window.
        oracle.recordObservation(KEY_WETH_USDC);

        // The newest observation should still match the first — same block state.
        ITWAPOracle.Observation memory obs2 = oracle.getLatestObservation(KEY_WETH_USDC);
        assertEq(obs2.price0Cumulative, obs.price0Cumulative, "cumulatives should match same-block observation");
        assertEq(obs2.timestamp, obs.timestamp, "timestamps should match same-block observation");
    }

    /// @notice After a single observation (registration), consult reverts with
    ///         TWAPInsufficientHistory.
    ///
    /// Fork limitation note: vm.warp advances local block.timestamp but the
    /// Uniswap V2 pair's blockTimestampLast is frozen at the fork block.  The
    /// pair's cumulatives only advance when its _update() runs during a swap.
    /// A 30-minute TWAP window test therefore cannot be exercised in this
    /// deterministic fork test without manipulating pair storage directly.
    ///
    /// TODO: use vm.store to poke price0CumulativeLast and blockTimestampLast
    ///       in the pair's storage layout to simulate a 30-minute accumulation,
    ///       then verify the TWAP result lies within a reasonable range.
    function test_Fork_ConsultThirtyMinuteWindow() public {
        vm.prank(admin);
        oracle.registerPair(KEY_WETH_USDC, UNIV2_WETH_USDC);

        // With only one observation recorded at registration, consult must revert.
        vm.expectRevert(abi.encodeWithSelector(ITWAPOracle.TWAPInsufficientHistory.selector, KEY_WETH_USDC));
        oracle.consult(KEY_WETH_USDC, 1800); // 30 minutes

        // TODO: To exercise the full TWAP path on a fork, advance the pair's
        //       cumulatives by poking its storage slots, warp 30 minutes, call
        //       recordObservation, then consult with windowSeconds=1800 and
        //       compare against the raw getReserves spot price.
    }

    /// @notice Immediately after registering a pair (one observation only),
    ///         consult must revert TWAPInsufficientHistory.
    function test_Fork_InsufficientHistoryReverts() public {
        vm.prank(admin);
        oracle.registerPair(KEY_WETH_USDC, UNIV2_WETH_USDC);

        // Only one observation has been stored (from registerPair).
        vm.expectRevert(abi.encodeWithSelector(ITWAPOracle.TWAPInsufficientHistory.selector, KEY_WETH_USDC));
        oracle.consult(KEY_WETH_USDC, 300);
    }
}
