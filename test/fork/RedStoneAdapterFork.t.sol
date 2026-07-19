// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IRedstonePriceFeedsAdapter} from "@lattice/interfaces/external/redstone/IRedstonePriceFeedsAdapter.sol";
import {IRedStoneAdapter} from "@lattice/interfaces/oracles/IRedStoneAdapter.sol";
import {RedStoneAdapter} from "@lattice/oracles/RedStoneAdapter.sol";
import {RedStoneAdapterLib} from "@lattice/oracles/libraries/RedStoneAdapterLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Mock diamond combining AccessControl + RedStoneAdapter.
contract MockRedStoneAdapterForkContract is AccessControl, RedStoneAdapter {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(AccessControl, RedStoneAdapter) returns (bytes memory) {}

    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        RedStoneAdapterLib.__RedStoneAdapter_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title RedStoneAdapterFork
/// @notice Fork test against a real RedStone Push PriceFeedsAdapter on Ethereum mainnet.
///
/// Enabling this test:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   export REDSTONE_ADAPTER=<PriceFeedsAdapter contract address>
///   export REDSTONE_DATA_FEED_ID=<bytes32 data-feed id, optional; defaults to bytes32("ETH")>
///   forge test --match-path "test/fork/RedStoneAdapterFork.t.sol"
///
/// RedStone Push deploys a PriceFeedsAdapter per data-package set (and predominantly on L2s) rather than at
/// a single canonical mainnet address, so the adapter address is supplied via the REDSTONE_ADAPTER env var.
/// The test is skipped unless both MAINNET_RPC_URL and REDSTONE_ADAPTER are set.
contract RedStoneAdapterFork is Test {
    /// @notice A recent mainnet block; overridable via REDSTONE_FORK_BLOCK for a fresher value.
    uint256 constant DEFAULT_FORK_BLOCK = 21_500_000;

    bytes32 constant KEY_ETH_USD = keccak256("ETH/USD");

    MockRedStoneAdapterForkContract adapter;
    address redstone;
    bytes32 dataFeedId;
    address admin = address(0x1);

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        redstone = vm.envOr("REDSTONE_ADAPTER", address(0));
        dataFeedId = vm.envOr("REDSTONE_DATA_FEED_ID", bytes32("ETH"));
        if (bytes(rpc).length == 0 || redstone == address(0)) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", vm.envOr("REDSTONE_FORK_BLOCK", DEFAULT_FORK_BLOCK));

        adapter = new MockRedStoneAdapterForkContract();
        adapter.initialize(admin);
    }

    /// @dev Registers ETH/USD with a staleness window covering the forked block's on-chain value age.
    function _registerEthUsd() internal {
        (, uint128 blockTimestamp) = IRedstonePriceFeedsAdapter(redstone).getTimestampsFromLatestUpdate();
        uint256 age = block.timestamp > blockTimestamp ? block.timestamp - blockTimestamp : 0;
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, redstone, dataFeedId, uint48(age + 1 hours));
    }

    function test_Fork_ETHUSDReadsLatestPrice() public {
        _registerEthUsd();

        (address storedAdapter, bytes32 storedId, uint48 maxStaleness) = adapter.getFeed(KEY_ETH_USD);
        assertEq(storedAdapter, redstone, "adapter mismatch");
        assertEq(storedId, dataFeedId, "dataFeedId mismatch");
        assertGt(maxStaleness, 0, "staleness set");

        int256 priceWad = adapter.latestAnswer(KEY_ETH_USD);
        // ETH/USD should be between $500 and $10,000 at any reasonable mainnet block.
        assertTrue(priceWad >= int256(500e18) && priceWad <= int256(10_000e18), "ETH/USD out of expected range");
    }

    function test_Fork_LatestAnswerMatchesScaledRaw() public {
        _registerEthUsd();

        (uint256 value,) = adapter.getValueForDataFeed(KEY_ETH_USD);
        // RedStone Push values are 8-decimals; WAD answer is the value scaled by 1e10.
        assertEq(adapter.latestAnswer(KEY_ETH_USD), int256(value * 1e10), "WAD scale mismatch");
    }
}
