// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IChainlinkAdapter} from "@lattice/interfaces/oracles/IChainlinkAdapter.sol";
import {ChainlinkAdapter} from "@lattice/oracles/chainlink/ChainlinkAdapter.sol";
import {ChainlinkAdapterLib} from "@lattice/oracles/chainlink/ChainlinkAdapterLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCK CONTRACT
// ---------------------------------------------------------------------------

/// @notice Mock Diamond that combines AccessControl + ChainlinkAdapter, matching
///         the pattern from ChainlinkAdapterTest.t.sol.
contract MockChainlinkAdapterForkContract is AccessControl, ChainlinkAdapter {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(AccessControl, ChainlinkAdapter) returns (bytes memory) {}

    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        s = InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        ChainlinkAdapterLib.__ChainlinkAdapter_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

// ---------------------------------------------------------------------------
//                              FORK TESTS
// ---------------------------------------------------------------------------

/// @title ChainlinkAdapterFork
/// @notice Fork tests that exercise ChainlinkAdapter against real Chainlink
///         price feeds on Ethereum mainnet.
///
/// Enabling fork tests:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   forge test --match-path "test/fork/*"
///
/// Without MAINNET_RPC_URL set, all tests in this contract are skipped.
contract ChainlinkAdapterFork is Test {
    // -------------------------------------------------------------------------
    //                         Mainnet addresses
    // -------------------------------------------------------------------------

    /// @notice Pinned mainnet block for deterministic results (December 2024).
    uint256 constant FORK_BLOCK = 21_500_000;

    /// @notice Chainlink ETH/USD aggregator (8 decimals).
    address constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    /// @notice Chainlink BTC/USD aggregator (8 decimals).
    address constant CHAINLINK_BTC_USD = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;

    bytes32 constant KEY_ETH_USD = keccak256("ETH/USD");
    bytes32 constant KEY_BTC_USD = keccak256("BTC/USD");

    uint48 constant STALENESS_1H = 3600;

    // -------------------------------------------------------------------------
    //                              State
    // -------------------------------------------------------------------------

    MockChainlinkAdapterForkContract adapter;
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

        adapter = new MockChainlinkAdapterForkContract();
        adapter.initialize(admin);
    }

    // -------------------------------------------------------------------------
    //                              Tests
    // -------------------------------------------------------------------------

    /// @notice Register the real ETH/USD feed and verify latestAnswer returns a
    ///         price in the range $500–$10,000 (normalised to 1e18).
    function test_Fork_ETHUSDFeedRegistersAndReadsLatestPrice() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, CHAINLINK_ETH_USD, STALENESS_1H);

        (address storedFeed, uint48 storedStaleness) = adapter.getFeed(KEY_ETH_USD);
        assertEq(storedFeed, CHAINLINK_ETH_USD, "feed address mismatch");
        assertEq(storedStaleness, STALENESS_1H, "staleness mismatch");

        int256 priceWad = adapter.latestAnswer(KEY_ETH_USD);

        // ETH/USD should be between $500 and $10,000 at any reasonable mainnet block.
        int256 lo = 500e18;
        int256 hi = 10_000e18;
        assertTrue(priceWad >= lo && priceWad <= hi, "ETH/USD out of expected range");
    }

    /// @notice Register the real BTC/USD feed and verify the price is in the
    ///         range $10,000–$500,000.
    function test_Fork_BTCUSDFeedRegistersAndReadsLatestPrice() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_BTC_USD, CHAINLINK_BTC_USD, STALENESS_1H);

        int256 priceWad = adapter.latestAnswer(KEY_BTC_USD);

        // BTC/USD should be between $10k and $500k.
        int256 lo = 10_000e18;
        int256 hi = 500_000e18;
        assertTrue(priceWad >= lo && priceWad <= hi, "BTC/USD out of expected range");
    }

    /// @notice Verify the decimal-normalisation math.
    ///         Chainlink ETH/USD has 8 decimals, so WAD = rawAnswer * 10^10.
    function test_Fork_LatestAnswerNormalizesTo18Decimals() public {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, CHAINLINK_ETH_USD, STALENESS_1H);

        (int256 rawAnswer,, uint8 decimals_) = adapter.latestAnswerRaw(KEY_ETH_USD);
        int256 priceWad = adapter.latestAnswer(KEY_ETH_USD);

        // Chainlink ETH/USD uses 8 decimals.
        assertEq(decimals_, 8, "expected 8-decimal feed");

        // Manual normalisation: rawAnswer * 10^(18 - 8) = rawAnswer * 10^10.
        int256 expectedWad = rawAnswer * int256(10 ** uint256(18 - uint256(decimals_)));
        assertEq(priceWad, expectedWad, "WAD normalisation mismatch");
    }

    /// @notice Register the ETH/USD feed with a generous staleness window first
    ///         to read updatedAt, then re-register with a 1-second window and
    ///         warp forward.  The call must revert with ChainlinkStaleData.
    function test_Fork_StalenessThresholdEnforced() public {
        // Register with a 1-hour window first so we can read updatedAt.
        vm.startPrank(admin);
        adapter.registerFeed(KEY_ETH_USD, CHAINLINK_ETH_USD, STALENESS_1H);
        vm.stopPrank();

        (, uint256 updatedAt,) = adapter.latestAnswerRaw(KEY_ETH_USD);

        // Warp forward 2 hours so the feed is definitely stale for a 1s window.
        vm.warp(block.timestamp + 7200);

        // Re-register with a 1-second staleness threshold.
        uint48 tinyWindow = 1;
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, CHAINLINK_ETH_USD, tinyWindow);

        vm.expectRevert(
            abi.encodeWithSelector(IChainlinkAdapter.ChainlinkStaleData.selector, KEY_ETH_USD, updatedAt, tinyWindow)
        );
        adapter.latestAnswer(KEY_ETH_USD);
    }
}
