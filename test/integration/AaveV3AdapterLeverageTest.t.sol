// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AaveV3Adapter} from "@lattice/defi/AaveV3Adapter.sol";
import {AaveV3AdapterLib} from "@lattice/defi/libraries/AaveV3AdapterLib.sol";
import {IAaveV3Adapter} from "@lattice/interfaces/defi/IAaveV3Adapter.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {ChainlinkAdapter} from "@lattice/oracles/chainlink/ChainlinkAdapter.sol";
import {ChainlinkAdapterLib} from "@lattice/oracles/chainlink/ChainlinkAdapterLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

import {MockAToken, MockAaveV3Pool, MockAsset} from "./AaveV3AdapterSupplyTest.t.sol";

//*//////////////////////////////////////////////////////////////////////////
//                      MOCK CHAINLINK AGGREGATOR FEED
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal AggregatorV3 feed: 8 decimals, configurable answer + updatedAt.
contract MockAggregator {
    int256 public answer;
    uint256 public updatedAt;
    uint8 public constant decimals = 8;

    constructor(int256 a) {
        answer = a;
        updatedAt = block.timestamp;
    }

    function setAnswer(int256 a) external {
        answer = a;
        updatedAt = block.timestamp;
    }

    function description() external pure returns (string memory) {
        return "USDC / USD";
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//             ADAPTER + CHAINLINK ADAPTER COMPOSED IN ONE DIAMOND
//////////////////////////////////////////////////////////////////////////*//

/// @notice The adapter facet AND the ChainlinkAdapter facet share one storage space, exactly as
///         they would in a real Diamond, so `ChainlinkAdapterLib.latestAnswer(feedKey)` reads the
///         feed registered here.
contract MockLeverAdapter is AaveV3Adapter, ChainlinkAdapter, Initializable {
    function initialize(
        address admin_,
        address provider_,
        address asset_,
        address vault_,
        address rewardRecipient_,
        bytes32 feedKey_,
        uint256 minHf_
    ) external initializer {
        AccessControlLib.__AccessControl_init(admin_);
        ChainlinkAdapterLib.__ChainlinkAdapter_init();
        AaveV3AdapterLib.__AaveV3Adapter_init(provider_, asset_, vault_, rewardRecipient_, feedKey_, minHf_);
    }

    function supportsInterface(bytes4 id) external view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

contract AaveV3AdapterLeverageTest is Test {
    MockAsset asset;
    MockAToken aToken;
    MockAaveV3Pool pool;
    MockLeverAdapter adapter;
    MockAggregator feed;

    address admin = address(0xAD);
    address vault = address(0x7A17);
    address treasury = address(0x7E0);
    bytes32 constant FEED_KEY = keccak256("USDC/USD");

    function setUp() public {
        asset = new MockAsset();
        aToken = new MockAToken(asset);
        pool = new MockAaveV3Pool();
        pool.setAToken(asset, aToken);
        // Seed the pool with extra liquidity so it can fund borrows.
        asset.mint(address(pool), 1_000_000e6);

        feed = new MockAggregator(1e8); // $1.00, 8 decimals

        adapter = new MockLeverAdapter();
        adapter.initialize(admin, address(pool), address(asset), vault, treasury, FEED_KEY, 1.1e18);

        vm.prank(admin);
        adapter.registerFeed(FEED_KEY, address(feed), 3600);
        // Authorize this test contract as the operator so the direct deploy/withdraw/harvest calls
        // (which the StrategyManager would make in production) pass the operator gate.
        vm.prank(admin);
        adapter.setOperator(address(this));

        // Supply initial collateral.
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();
    }

    function test_Lever_BorrowsAndResupplies_IncreasingCollateral() public {
        // Borrow 500, re-supply: collateral 1500, debt 500. HF = 1500*0.8/500 = 2.4 >= 1.10.
        // lever/delever are operator-gated (this test contract is the wired operator).
        adapter.lever(500e6);

        assertEq(aToken.balanceOf(address(adapter)), 1_500e6, "collateral grew by borrow");
        assertEq(pool.debt(address(adapter)), 500e6, "debt recorded");
        // HF well above floor.
        assertGt(adapter.healthFactor(), 1.1e18, "HF healthy");
    }

    function test_NetEquityValuation_WhenLevered() public {
        adapter.lever(500e6);
        // Net equity = collateral - debt = 1500 - 500 = 1000 (in asset units, Aave price $1).
        assertApproxEqAbs(adapter.totalAssetsManaged(), 1_000e6, 1, "net equity == initial capital");
    }

    function test_Lever_RevertsWhenItWouldBreachFloor() public {
        // Floor 1.10. To breach: borrow so much that HF < 1.10.
        // collateral after = 1000 + b; debt = b; HF = (1000+b)*0.8 / b.
        // Solve HF=1.10 -> 0.8*(1000+b) = 1.10*b -> 800 = 0.30*b -> b ~= 2666. Borrow 5000 => HF<1.10.
        vm.expectRevert(); // ProtocolAdapterHealthFactorBreached (resulting < floor)
        adapter.lever(5_000e6);
    }

    function test_Delever_RepaysDebtAndRestoresHealthFactor() public {
        adapter.lever(500e6);
        uint256 hfBefore = adapter.healthFactor();

        // Pull 300 collateral and repay 300 debt.
        uint256 repaid = adapter.delever(300e6);
        assertEq(repaid, 300e6, "repaid the pulled amount");
        assertEq(pool.debt(address(adapter)), 200e6, "debt reduced");
        assertGt(adapter.healthFactor(), hfBefore, "HF improved after delever");
    }

    function test_LiquidationTolerance_TotalAssetsDropsAndWithdrawHonest() public {
        adapter.lever(500e6); // collateral 1500, debt 500, net 1000

        // Simulate an external partial liquidation: the protocol seizes 400 collateral
        // (aToken burned) while debt is unchanged. Net equity should drop to 1100-... we
        // compute: collateral 1100, debt 500 => net 600.
        vm.prank(address(pool)); // pool is the only one that can burn in the mock
        aToken.burn(address(adapter), 400e6);

        // Valuation reflects the loss honestly (no revert, no stale NAV).
        assertApproxEqAbs(adapter.totalAssetsManaged(), 600e6, 1, "net equity dropped post-liquidation");

        // Withdraw returns the REAL amount; ask 1000 but only ~600 equity / 1100 collateral exists.
        uint256 got = adapter.withdraw(1_000e6, vault);
        assertLe(got, 1_100e6, "honest: capped at withdrawable collateral");
        assertGt(got, 0, "some funds returned");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //         ITEM 1 — NET EQUITY USES AAVE'S OWN ORACLE (no cross-oracle drift)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Levered net-equity valuation must be priced by Aave's OWN oracle (the same source that
    ///         denominates getUserAccountData), NOT the separate Lattice ChainlinkAdapter feed. Here
    ///         the Lattice feed and Aave's price DIVERGE while debt > 0: post-fix `totalAssetsManaged`
    ///         tracks Aave's self-consistent figure and is INDEPENDENT of the Lattice feed.
    ///
    ///         Pre-fix (Lattice-feed divisor): netBase8 = (collat-debt) priced by Aave's price; the
    ///         divisor was the Lattice feed, so moving the Lattice feed moved NAV. Post-fix the divisor
    ///         is Aave's price, so the Lattice feed has zero effect on the levered NAV.
    function test_NetEquity_UsesAaveOracle_IndependentOfLatticeFeed() public {
        adapter.lever(500e6); // collateral 1500, debt 500 (both at Aave price $1) => net equity 1000

        // Baseline: Aave price $1, Lattice feed $1 -> 1000 asset units.
        assertApproxEqAbs(adapter.totalAssetsManaged(), 1_000e6, 1, "baseline net equity 1000");

        // Diverge ONLY the Lattice feed (e.g. depeg/mis-registered key): $1.00 -> $1.25. Aave's price
        // is unchanged. Post-fix this MUST NOT move the levered NAV (Aave oracle is the sole source).
        feed.setAnswer(1.25e8);
        assertApproxEqAbs(
            adapter.totalAssetsManaged(), 1_000e6, 1, "NAV independent of Lattice feed (Aave oracle is the source)"
        );

        // Now move AAVE's price the same way: $1.00 -> $1.25 for BOTH legs. Net base = (1500-500)*1.25
        // = 1250 base8; assetUnits = netBase8 * 10^6 / 1.25e8 = 1000e6 (single-asset loop: price
        // cancels, equity stays 1000 asset units). This proves the conversion divides by Aave's price.
        pool.setPrice(1.25e8);
        assertApproxEqAbs(
            adapter.totalAssetsManaged(), 1_000e6, 1, "single-asset loop: equity invariant under Aave price move"
        );
    }

    /// @notice The levered valuation no longer reads the Lattice feed, so an externally STALE Lattice
    ///         feed does not affect (or revert) `totalAssetsManaged()`. (Pre-fix this reverted with
    ///         ChainlinkStaleData; post-fix the Aave oracle is the only price source.)
    function test_NetEquity_DoesNotRevertOnStaleLatticeFeed() public {
        adapter.lever(500e6);
        // Warp far past the Lattice feed's staleness window. The Aave-oracle path ignores it.
        vm.warp(block.timestamp + 7200);
        assertApproxEqAbs(adapter.totalAssetsManaged(), 1_000e6, 1, "valuation unaffected by stale Lattice feed");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //              ITEM 2 — lever/delever ARE OPERATOR-GATED
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice `lever` is operator-gated: a permissionless caller (here even `admin`, who is NOT the
    ///         operator) cannot force leverage up. Pre-fix this was ungated (risk/timing griefing).
    function test_Lever_RevertsForNonOperator() public {
        vm.prank(admin); // admin is NOT the operator (operator == this test contract)
        vm.expectRevert(abi.encodeWithSelector(IProtocolAdapter.ProtocolAdapterUnauthorized.selector, admin));
        adapter.lever(500e6);

        assertEq(pool.debt(address(adapter)), 0, "no leverage taken by unauthorized caller");
    }

    /// @notice `delever` is operator-gated: a permissionless caller cannot force-unwind leverage.
    function test_Delever_RevertsForNonOperator() public {
        adapter.lever(500e6); // operator opens a position
        assertEq(pool.debt(address(adapter)), 500e6, "position open");

        address attacker = address(0xBAD);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(IProtocolAdapter.ProtocolAdapterUnauthorized.selector, attacker));
        adapter.delever(300e6);

        assertEq(pool.debt(address(adapter)), 500e6, "debt unchanged: unauthorized delever rejected");
    }

    /// @notice With NO operator wired, lever/delever revert for everyone (secure default).
    function test_LeverDelever_RevertWhenOperatorUnset() public {
        // Fresh adapter with no operator set.
        MockLeverAdapter fresh = new MockLeverAdapter();
        fresh.initialize(admin, address(pool), address(asset), vault, treasury, FEED_KEY, 1.1e18);

        vm.expectRevert(abi.encodeWithSelector(IProtocolAdapter.ProtocolAdapterUnauthorized.selector, address(this)));
        fresh.lever(100e6);

        vm.expectRevert(abi.encodeWithSelector(IProtocolAdapter.ProtocolAdapterUnauthorized.selector, address(this)));
        fresh.delever(100e6);
    }

    /// @notice The authorized operator can lever AND delever, with the position changing as before.
    function test_Authorized_LeverAndDelever_Succeed() public {
        adapter.lever(500e6);
        assertEq(pool.debt(address(adapter)), 500e6, "operator levered");

        uint256 repaid = adapter.delever(200e6);
        assertEq(repaid, 200e6, "operator delevered");
        assertEq(pool.debt(address(adapter)), 300e6, "debt reduced by operator");
    }
}
