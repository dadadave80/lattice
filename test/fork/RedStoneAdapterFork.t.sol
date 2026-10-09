// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {ArchiveFork} from "@lattice-test/helpers/ArchiveFork.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IRedstonePriceFeedsAdapter} from "@lattice/interfaces/external/redstone/IRedstonePriceFeedsAdapter.sol";
import {IRedStoneAdapter} from "@lattice/interfaces/oracles/IRedStoneAdapter.sol";
import {RedStoneAdapter} from "@lattice/oracles/redstone/RedStoneAdapter.sol";
import {RedStoneAdapterLib} from "@lattice/oracles/redstone/RedStoneAdapterLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Mock diamond combining AccessControl + RedStoneAdapter.
contract MockRedStoneAdapterForkContract is AccessControl, RedStoneAdapter, Initializable {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(AccessControl, RedStoneAdapter) returns (bytes memory) {}

    function initialize(address _admin) external initializer {
        AccessControlLib.__AccessControl_init(_admin);
        RedStoneAdapterLib.__RedStoneAdapter_init();
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title RedStoneAdapterFork
/// @notice Fork test against a real RedStone Push PriceFeedsAdapter on Ethereum mainnet.
///
/// Enabling this test:
///   export MAINNET_RPC_URL=<your-archive-rpc-url>
///   forge test --match-path "test/fork/RedStoneAdapterFork.t.sol"
///
/// Without MAINNET_RPC_URL set, all tests here are skipped. The fork is pinned (REDSTONE_FORK_BLOCK overrides
/// it), so it needs an archive endpoint. RedStone Push deploys one adapter per data-package set rather than a
/// single mainnet address. The default is RedStone's ether.fi weETH/USD adapter, a classic PriceFeedsAdapter
/// with one data feed (`weETH`, 8 decimals) whose USD price sits in the same range as ETH/USD.
/// REDSTONE_ADAPTER and REDSTONE_DATA_FEED_ID override the adapter and feed id. The feed id defaults to `weETH`
/// (it was `ETH` before the default adapter existed), so set REDSTONE_DATA_FEED_ID too when overriding
/// REDSTONE_ADAPTER with an adapter that does not serve `weETH`. RedStone's mainnet ETH feed
/// lives on its multi-feed adapter, which does not implement `getTimestampsFromLatestUpdate()`, so
/// RedStoneAdapter cannot read it.
contract RedStoneAdapterFork is Test {
    /// @notice Pinned mainnet block (December 2024), shared with the other mainnet oracle suites.
    uint256 constant DEFAULT_FORK_BLOCK = 21_500_000;

    /// @notice RedStone's mainnet ether.fi weETH PriceFeedsAdapter, from its relayer manifest
    ///         (https://github.com/redstone-finance/redstone-oracles-monorepo/blob/1b460898e6b65e5f9a81a1f044141022a9ffa2ce/packages/relayer-remote-config/main/relayer-manifests/ethereumEtherfiWeeth.json).
    address constant WEETH_PRICE_FEEDS_ADAPTER = 0xdDb6F90fFb4d3257dd666b69178e5B3c5Bf41136;

    bytes32 constant KEY_WEETH_USD = keccak256("weETH/USD");

    MockRedStoneAdapterForkContract adapter;
    address redstone;
    bytes32 dataFeedId;
    address admin = address(0x1);

    function setUp() public {
        if (bytes(vm.envOr("MAINNET_RPC_URL", string(""))).length == 0) {
            vm.skip(true);
            return;
        }
        redstone = vm.envOr("REDSTONE_ADAPTER", WEETH_PRICE_FEEDS_ADAPTER);
        dataFeedId = vm.envOr("REDSTONE_DATA_FEED_ID", bytes32("weETH"));
        if (!ArchiveFork.select("mainnet", vm.envOr("REDSTONE_FORK_BLOCK", DEFAULT_FORK_BLOCK))) return;
        // The pin postdates the adapter, so missing code means a wrong address or pin: skip locally, fail on the
        // strict weekly lane.
        if (redstone.code.length == 0) {
            ArchiveFork.skipOrFail(ArchiveFork.strict(), "RedStone PriceFeedsAdapter has no code at the fork block");
            return;
        }
        // The adapter serves the feed id, and is the classic kind RedStoneAdapter reads.
        (bool ok, bytes memory ret) = redstone.staticcall(abi.encodeWithSignature("getDataFeedIds()"));
        assertTrue(ok, "getDataFeedIds() reverted");
        bytes32[] memory ids = abi.decode(ret, (bytes32[]));
        bool served;
        for (uint256 i; i < ids.length; ++i) {
            if (ids[i] == dataFeedId) served = true;
        }
        assertTrue(served, "adapter does not serve REDSTONE_DATA_FEED_ID (default weETH)");
        IRedstonePriceFeedsAdapter(redstone).getTimestampsFromLatestUpdate();

        adapter = new MockRedStoneAdapterForkContract();
        adapter.initialize(admin);
    }

    /// @dev Registers weETH/USD with a staleness window covering the forked block's on-chain value age.
    function _registerFeed() internal {
        (, uint128 blockTimestamp) = IRedstonePriceFeedsAdapter(redstone).getTimestampsFromLatestUpdate();
        uint256 age = block.timestamp > blockTimestamp ? block.timestamp - blockTimestamp : 0;
        vm.prank(admin);
        adapter.registerFeed(KEY_WEETH_USD, redstone, dataFeedId, uint48(age + 1 hours));
    }

    function test_Fork_WEETHUSDReadsLatestPrice() public {
        _registerFeed();

        (address storedAdapter, bytes32 storedId, uint48 maxStaleness) = adapter.getFeed(KEY_WEETH_USD);
        assertEq(storedAdapter, redstone, "adapter mismatch");
        assertEq(storedId, dataFeedId, "dataFeedId mismatch");
        assertGt(maxStaleness, 0, "staleness set");

        int256 priceWad = adapter.latestAnswer(KEY_WEETH_USD);
        // weETH/USD tracks ETH/USD (a weETH is worth slightly more than an ETH): between $500 and $10,000.
        assertTrue(priceWad >= int256(500e18) && priceWad <= int256(10_000e18), "weETH/USD out of expected range");
    }

    /// @notice The default adapter is the classic weETH PriceFeedsAdapter: one 8-decimal `weETH` feed.
    function test_Fork_DefaultAdapterIsWeethPriceFeedsAdapter() public view {
        (bool ok, bytes memory ret) = WEETH_PRICE_FEEDS_ADAPTER.staticcall(abi.encodeWithSignature("getDataFeedIds()"));
        assertTrue(ok, "getDataFeedIds() reverted");
        bytes32[] memory ids = abi.decode(ret, (bytes32[]));
        assertEq(ids.length, 1, "expected a single data feed");
        assertEq(ids[0], bytes32("weETH"), "not the weETH feed");

        (ok, ret) = WEETH_PRICE_FEEDS_ADAPTER.staticcall(abi.encodeWithSignature("decimals()"));
        assertTrue(ok, "decimals() reverted");
        assertEq(abi.decode(ret, (uint8)), 8, "not 8 decimals");
    }

    function test_Fork_LatestAnswerMatchesScaledRaw() public {
        _registerFeed();

        (uint256 value,) = adapter.getValueForDataFeed(KEY_WEETH_USD);
        // RedStone Push values are 8-decimals; WAD answer is the value scaled by 1e10.
        assertEq(adapter.latestAnswer(KEY_WEETH_USD), int256(value * 1e10), "WAD scale mismatch");
    }
}
