// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ConstantProduct} from "@lattice/amm/ConstantProduct.sol";
import {ConstantProductLib} from "@lattice/amm/libraries/ConstantProductLib.sol";
import {IConstantProduct} from "@lattice/interfaces/amm/IConstantProduct.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCK CONTRACT
// ---------------------------------------------------------------------------

/// @notice Mock Diamond that combines AccessControl + ConstantProduct, matching
///         the pattern from ConstantProductTest.t.sol.
contract MockConstantProductFork is ConstantProduct, AccessControl {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(ConstantProduct, AccessControl) returns (bytes memory) {}

    function initialize(address token0_, address token1_, address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        ConstantProductLib.__ConstantProduct_init(token0_, token1_);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 interfaceId_) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId_);
    }
}

// ---------------------------------------------------------------------------
//                              FORK TESTS
// ---------------------------------------------------------------------------

/// @title ConstantProductFork
/// @notice Fork tests that exercise ConstantProduct against real mainnet ERC-20
///         tokens (WETH and USDC) on Ethereum mainnet.
///
/// Enabling fork tests:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   forge test --match-path "test/fork/*"
///
/// Without MAINNET_RPC_URL set, all tests in this contract are skipped.
contract ConstantProductFork is Test {
    // -------------------------------------------------------------------------
    //                         Mainnet addresses
    // -------------------------------------------------------------------------

    /// @notice Pinned mainnet block for deterministic results (December 2024).
    uint256 constant FORK_BLOCK = 21_500_000;

    /// @notice WETH on mainnet (18 decimals).
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @notice USDC on mainnet (6 decimals).
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 constant MINIMUM_LIQUIDITY = 1000;

    // -------------------------------------------------------------------------
    //                              State
    // -------------------------------------------------------------------------

    MockConstantProductFork pool;
    address admin = address(0xA11CE);

    // Expected token order after the pool sorts by address.
    address expectedToken0;
    address expectedToken1;

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

        pool = new MockConstantProductFork();
        pool.initialize(WETH, USDC, admin);

        // Determine sorted order.
        expectedToken0 = WETH < USDC ? WETH : USDC;
        expectedToken1 = WETH < USDC ? USDC : WETH;
    }

    // -------------------------------------------------------------------------
    //                              Tests
    // -------------------------------------------------------------------------

    /// @notice Initialise ConstantProduct with real WETH + USDC addresses.
    ///         Verify token0 < token1 (sorted by address) and feeBps == 30.
    function test_Fork_InitializeWithRealTokenAddresses() public view {
        address t0 = pool.token0();
        address t1 = pool.token1();

        assertEq(t0, expectedToken0, "token0 should be the lower address");
        assertEq(t1, expectedToken1, "token1 should be the higher address");
        assertTrue(t0 < t1, "token0 must be < token1 after sort");
        assertEq(pool.feeBps(), 30, "fee should be 30 bps");
    }

    /// @notice Add liquidity using real WETH and USDC balances obtained via deal().
    ///         Verify LP shares received and reserves match the deposited amounts.
    ///
    ///         Amounts: 100 WETH + 300,000 USDC (approx $3,000/ETH).
    ///         Note: USDC uses 6 decimals, so 300_000 USDC = 300_000 * 1e6.
    function test_Fork_AddLiquidityWithRealTokens() public {
        uint256 wethAmount = 100 ether; // 100 WETH (18 decimals)
        uint256 usdcAmount = 300_000 * 1e6; // 300,000 USDC (6 decimals)

        // Fund this test contract with real token balances using forge-std's deal.
        deal(WETH, address(this), wethAmount);
        deal(USDC, address(this), usdcAmount);

        assertEq(IERC20(WETH).balanceOf(address(this)), wethAmount, "WETH deal failed");
        assertEq(IERC20(USDC).balanceOf(address(this)), usdcAmount, "USDC deal failed");

        // Approve the pool for both tokens.
        IERC20(WETH).approve(address(pool), wethAmount);
        IERC20(USDC).approve(address(pool), usdcAmount);

        // Determine which direction to pass amounts (pool is sorted).
        uint256 amount0Desired = expectedToken0 == WETH ? wethAmount : usdcAmount;
        uint256 amount1Desired = expectedToken0 == WETH ? usdcAmount : wethAmount;

        (uint256 used0, uint256 used1, uint256 liquidity) =
            pool.addLiquidity(amount0Desired, amount1Desired, 0, 0, address(this));

        // Both full amounts should have been consumed (first deposit sets the ratio).
        assertEq(used0, amount0Desired, "all token0 should be used on first deposit");
        assertEq(used1, amount1Desired, "all token1 should be used on first deposit");

        // LP received = sqrt(used0 * used1) - MINIMUM_LIQUIDITY (first deposit).
        // We just verify it is positive and greater than MINIMUM_LIQUIDITY.
        assertTrue(liquidity > 0, "LP shares must be positive");
        assertEq(pool.lpBalanceOf(address(this)), liquidity, "LP balance mismatch");
        assertEq(pool.lpBalanceOf(address(1)), MINIMUM_LIQUIDITY, "MINIMUM_LIQUIDITY not locked to address(1)");

        // Reserves must equal the deposited amounts.
        (uint256 r0, uint256 r1,) = pool.getReserves();
        assertEq(r0, amount0Desired, "reserve0 mismatch after addLiquidity");
        assertEq(r1, amount1Desired, "reserve1 mismatch after addLiquidity");
    }

    /// @notice After adding liquidity, swap 1 WETH for USDC.
    ///         Verify USDC received is within 1% of the spot price implied by
    ///         pool reserves (accounting for the 0.3% fee and slippage).
    function test_Fork_SwapWETHForUSDC() public {
        // --- Setup: seed the pool with 100 WETH + 300,000 USDC ---
        uint256 wethSeed = 100 ether;
        uint256 usdcSeed = 300_000 * 1e6;

        deal(WETH, address(this), wethSeed + 1 ether); // extra 1 WETH for the swap
        deal(USDC, address(this), usdcSeed);

        IERC20(WETH).approve(address(pool), wethSeed);
        IERC20(USDC).approve(address(pool), usdcSeed);

        uint256 amount0Seed = expectedToken0 == WETH ? wethSeed : usdcSeed;
        uint256 amount1Seed = expectedToken0 == WETH ? usdcSeed : wethSeed;

        pool.addLiquidity(amount0Seed, amount1Seed, 0, 0, address(this));

        // --- Swap 1 WETH for USDC ---
        uint256 swapIn = 1 ether; // 1 WETH

        IERC20(WETH).approve(address(pool), swapIn);

        uint256 usdcBefore = IERC20(USDC).balanceOf(address(this));

        // zeroForOne = true when swapping token0 for token1.
        // Determine direction: if WETH is token0, zeroForOne = true; else false.
        bool zeroForOne = expectedToken0 == WETH;
        uint256 amountOut = pool.swapExactTokensForTokens(swapIn, 0, zeroForOne, address(this));

        uint256 usdcAfter = IERC20(USDC).balanceOf(address(this));
        assertEq(usdcAfter - usdcBefore, amountOut, "USDC balance delta should match amountOut");

        // --- Sanity check: amountOut is within 1% of the no-fee spot price ---
        // Spot price with no fee: reserveUSDC / reserveWETH * swapIn
        // At 100 WETH : 300_000 USDC the spot is 3000 USDC per WETH.
        // After the 0.3% fee + slippage the output should be slightly less.
        // We accept anything between 2940 USDC (2% below spot) and 3000 USDC.
        uint256 spotNoFee = 3000 * 1e6; // 3000 USDC (6 decimals)
        uint256 lowerBound = (spotNoFee * 98) / 100; // 2% tolerance covers fee + slippage
        assertTrue(amountOut >= lowerBound, "swap output below 2% lower bound");
        assertTrue(amountOut <= spotNoFee, "swap output cannot exceed no-fee spot price");
    }
}
