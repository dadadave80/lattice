// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {ConstantProductTestBase} from "@lattice-test/base/ConstantProductTestBase.sol";
import {IMintableToken} from "@lattice-test/helpers/IMintableToken.sol";
import {ConstantProduct} from "@lattice/amm/ConstantProduct.sol";
import {IConstantProduct} from "@lattice/interfaces/amm/IConstantProduct.sol";
import {IReentrancyGuard} from "@lattice/interfaces/security/IReentrancyGuard.sol";

//*//////////////////////////////////////////////////////////////////////////
//                               TEST ERC-20
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal ERC-20 used by ConstantProduct tests.
contract TestERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                   TESTS
//////////////////////////////////////////////////////////////////////////*//

/// @title ConstantProductTest
/// @notice Exercises the ConstantProduct AMM facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployConstantProduct} script (see {ConstantProductTestBase}) — every pool call routes through the
///         diamond's `delegatecall` dispatch, not a flattened inheritance mock. The two reserve tokens are REAL
///         base ERC-20 diamonds ({DeployERC20} + {TokenTestFacet}); `supportsInterface` comes from the cut-in
///         `ERC165Facet`. The malicious-token fixtures below are EXTERNAL attackers the pool transacts with —
///         NOT the facet under test.
contract ConstantProductTest is ConstantProductTestBase {
    address diamond; // the assembled pool diamond
    ConstantProduct pool; // typed handle on the pool diamond
    IMintableToken token0; // lower address after sort (real ERC-20 diamond)
    IMintableToken token1; // higher address after sort (real ERC-20 diamond)

    address admin = address(0xA11CE);
    address alice = address(0xA11CE2);
    address bob = address(0xB0B);

    uint256 constant MINIMUM_LIQUIDITY = 1000;

    function setUp() public {
        // Deploy two real base ERC-20 diamonds as the pair reserve tokens.
        address ta = _deployMintableERC20("TokenA", "TKA");
        address tb = _deployMintableERC20("TokenB", "TKB");

        // Determine sort order so tests can refer to token0/token1 unambiguously.
        (address t0Addr, address t1Addr) = ta < tb ? (ta, tb) : (tb, ta);
        token0 = IMintableToken(t0Addr);
        token1 = IMintableToken(t1Addr);

        diamond = _deployPool(admin, ta, tb);
        pool = ConstantProduct(diamond);

        // Mint tokens to alice and bob.
        token0.mint(alice, 1_000_000e18);
        token1.mint(alice, 1_000_000e18);
        token0.mint(bob, 1_000_000e18);
        token1.mint(bob, 1_000_000e18);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializing with identical token addresses reverts.
    function test_InitSameTokenReverts() public {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            _buildPoolCuts(admin, address(token0), address(token0));
        Diamond d = new Diamond();
        vm.expectRevert(IConstantProduct.ConstantProductInvalidTokens.selector);
        d.initialize(cuts, init, initCalldata);
    }

    /// @notice Initializing with zero token0 reverts.
    function test_InitZeroToken0Reverts() public {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            _buildPoolCuts(admin, address(0), address(token1));
        Diamond d = new Diamond();
        vm.expectRevert(IConstantProduct.ConstantProductInvalidTokens.selector);
        d.initialize(cuts, init, initCalldata);
    }

    /// @notice Initializing with zero token1 reverts.
    function test_InitZeroToken1Reverts() public {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            _buildPoolCuts(admin, address(token0), address(0));
        Diamond d = new Diamond();
        vm.expectRevert(IConstantProduct.ConstantProductInvalidTokens.selector);
        d.initialize(cuts, init, initCalldata);
    }

    /// @notice Tokens are always sorted: token0 < token1 by address.
    function test_InitSortsTokens() public view {
        address t0 = pool.token0();
        address t1 = pool.token1();
        assertTrue(t0 < t1, "token0 should be the lower address");
        // One of the two supplied tokens must be each slot.
        assertTrue(
            (t0 == address(token0) || t0 == address(token1)) && (t1 == address(token0) || t1 == address(token1)),
            "tokens should match supplied addresses"
        );
    }

    /// @notice feeBps is always 30.
    function test_FeeBpsIs30() public view {
        assertEq(pool.feeBps(), 30);
    }

    /// @notice ERC-165 reports IConstantProduct support.
    function test_SupportsInterfaceIConstantProduct() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IConstantProduct).interfaceId));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          FIRST LIQUIDITY DEPOSIT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice First deposit mints sqrt(a*b) - MINIMUM_LIQUIDITY shares to the provider.
    function test_FirstDepositMintsCorrectShares() public {
        uint256 a0 = 100e18;
        uint256 a1 = 400e18;

        vm.startPrank(alice);
        token0.approve(address(pool), a0);
        token1.approve(address(pool), a1);
        (,, uint256 liquidity) = pool.addLiquidity(a0, a1, 0, 0, alice);
        vm.stopPrank();

        // sqrt(100e18 * 400e18) = sqrt(40000e36) = 200e18
        uint256 expected = 200e18 - MINIMUM_LIQUIDITY;
        assertEq(liquidity, expected, "wrong LP amount for first deposit");
        assertEq(pool.lpBalanceOf(alice), expected);
        assertEq(pool.lpBalanceOf(address(1)), MINIMUM_LIQUIDITY, "MINIMUM_LIQUIDITY not locked");
        assertEq(pool.totalLpSupply(), expected + MINIMUM_LIQUIDITY);
    }

    /// @notice Reserves are updated correctly after first deposit.
    function test_FirstDepositUpdatesReserves() public {
        uint256 a0 = 100e18;
        uint256 a1 = 400e18;

        vm.startPrank(alice);
        token0.approve(address(pool), a0);
        token1.approve(address(pool), a1);
        pool.addLiquidity(a0, a1, 0, 0, alice);
        vm.stopPrank();

        (uint256 r0, uint256 r1,) = pool.getReserves();
        assertEq(r0, a0);
        assertEq(r1, a1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         SUBSEQUENT LIQUIDITY DEPOSIT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Subsequent deposit uses the lower optimal amount.
    function test_SubsequentDepositUsesOptimalAmounts() public {
        // First deposit: set ratio 1:4 (token0:token1).
        vm.startPrank(alice);
        token0.approve(address(pool), 100e18);
        token1.approve(address(pool), 400e18);
        pool.addLiquidity(100e18, 400e18, 0, 0, alice);
        vm.stopPrank();

        // Second deposit: alice provides more — exact ratio 1:4.
        vm.startPrank(alice);
        token0.approve(address(pool), 10e18);
        token1.approve(address(pool), 40e18);
        (uint256 used0, uint256 used1,) = pool.addLiquidity(10e18, 40e18, 0, 0, alice);
        vm.stopPrank();

        assertEq(used0, 10e18, "should use all token0");
        assertEq(used1, 40e18, "should use all token1");
    }

    /// @notice If desired amounts exceed pool ratio on token1 side, token0 becomes binding.
    function test_SubsequentDepositCapsByToken1() public {
        // Set ratio 1:4.
        vm.startPrank(alice);
        token0.approve(address(pool), 100e18);
        token1.approve(address(pool), 400e18);
        pool.addLiquidity(100e18, 400e18, 0, 0, alice);
        vm.stopPrank();

        // Provide too much token0 relative to token1Desired.
        // Ratio: 1:4 → for 20 token1, optimal token0 = 5.
        vm.startPrank(bob);
        token0.approve(address(pool), 10e18);
        token1.approve(address(pool), 20e18);
        (uint256 used0, uint256 used1,) = pool.addLiquidity(10e18, 20e18, 0, 0, bob);
        vm.stopPrank();

        // token1 is the binding constraint: amount1 = 20e18, amount0 = quote(20e18, 400e18, 100e18) = 5e18.
        assertEq(used1, 20e18, "token1 should be binding");
        assertEq(used0, 5e18, "token0 should be back-calculated");
    }

    /// @notice Slippage guard on amount0Min reverts if not satisfied.
    function test_AddLiquidityRevertsIfAmount0MinNotMet() public {
        // Set ratio 1:4.
        vm.startPrank(alice);
        token0.approve(address(pool), 100e18);
        token1.approve(address(pool), 400e18);
        pool.addLiquidity(100e18, 400e18, 0, 0, alice);
        vm.stopPrank();

        // Require token0 >= 6 but only 5 fits.
        vm.startPrank(bob);
        token0.approve(address(pool), 10e18);
        token1.approve(address(pool), 20e18);
        // amount0Min = 6e18 but optimal is 5e18 → should revert.
        vm.expectRevert(IConstantProduct.ConstantProductSlippageExceeded.selector);
        pool.addLiquidity(10e18, 20e18, 6e18, 0, bob);
        vm.stopPrank();
    }

    /// @notice Slippage guard on amount1Min reverts if not satisfied.
    function test_AddLiquidityRevertsIfAmount1MinNotMet() public {
        vm.startPrank(alice);
        token0.approve(address(pool), 100e18);
        token1.approve(address(pool), 400e18);
        pool.addLiquidity(100e18, 400e18, 0, 0, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        token0.approve(address(pool), 10e18);
        token1.approve(address(pool), 400e18); // provide way more than needed
        // optimal amount1 = 40e18, amount1Min = 41e18 → revert.
        vm.expectRevert(IConstantProduct.ConstantProductSlippageExceeded.selector);
        pool.addLiquidity(10e18, 400e18, 0, 41e18, bob);
        vm.stopPrank();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            REMOVE LIQUIDITY
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Removing all (non-locked) LP shares returns proportional amounts.
    function test_RemoveLiquidityReturnsProportionalAmounts() public {
        uint256 a0 = 100e18;
        uint256 a1 = 400e18;

        vm.startPrank(alice);
        token0.approve(address(pool), a0);
        token1.approve(address(pool), a1);
        (,, uint256 aliceLp) = pool.addLiquidity(a0, a1, 0, 0, alice);
        vm.stopPrank();

        uint256 totalLp = pool.totalLpSupply(); // includes MINIMUM_LIQUIDITY

        uint256 balanceBefore0 = token0.balanceOf(alice);
        uint256 balanceBefore1 = token1.balanceOf(alice);

        vm.startPrank(alice);
        (uint256 out0, uint256 out1) = pool.removeLiquidity(aliceLp, 0, 0, alice);
        vm.stopPrank();

        // out = (aliceLp / totalLp) * reserve
        uint256 expected0 = (aliceLp * a0) / totalLp;
        uint256 expected1 = (aliceLp * a1) / totalLp;

        assertEq(out0, expected0, "wrong token0 returned");
        assertEq(out1, expected1, "wrong token1 returned");
        assertEq(token0.balanceOf(alice), balanceBefore0 + out0);
        assertEq(token1.balanceOf(alice), balanceBefore1 + out1);
        assertEq(pool.lpBalanceOf(alice), 0);
    }

    /// @notice removeLiquidity reverts when amount0Min is not met.
    function test_RemoveLiquidityRevertsAmount0MinNotMet() public {
        vm.startPrank(alice);
        token0.approve(address(pool), 100e18);
        token1.approve(address(pool), 400e18);
        (,, uint256 lp) = pool.addLiquidity(100e18, 400e18, 0, 0, alice);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(IConstantProduct.ConstantProductSlippageExceeded.selector);
        pool.removeLiquidity(lp, type(uint256).max, 0, alice);
        vm.stopPrank();
    }

    /// @notice removeLiquidity reverts when amount1Min is not met.
    function test_RemoveLiquidityRevertsAmount1MinNotMet() public {
        vm.startPrank(alice);
        token0.approve(address(pool), 100e18);
        token1.approve(address(pool), 400e18);
        (,, uint256 lp) = pool.addLiquidity(100e18, 400e18, 0, 0, alice);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(IConstantProduct.ConstantProductSlippageExceeded.selector);
        pool.removeLiquidity(lp, 0, type(uint256).max, alice);
        vm.stopPrank();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              SWAP TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice getAmountOut matches the Uniswap V2 formula with 0.3% fee.
    function test_GetAmountOutFormula() public view {
        // amountInWithFee = 1000 * 9970 = 9970000
        // numerator = 9970000 * 100000 = 997000000000
        // denominator = 100000 * 10000 + 9970000 = 1009970000
        // out = 997000000000 / 1009970000 = 987 (floor)
        uint256 amountIn = 1000;
        uint256 reserveIn = 100_000;
        uint256 reserveOut = 100_000;
        uint256 out = pool.getAmountOut(amountIn, reserveIn, reserveOut);
        // Manual: floor(9970000 * 100000 / (100000*10000 + 9970000))
        //       = floor(997000000000 / 1009970000) = 987
        assertEq(out, 987, "getAmountOut mismatch");
    }

    /// @notice getAmountIn is the inverse of getAmountOut (up to rounding).
    function test_GetAmountInIsInverse() public view {
        uint256 reserveIn = 100_000;
        uint256 reserveOut = 100_000;
        uint256 amountIn = 1000;
        uint256 amountOut = pool.getAmountOut(amountIn, reserveIn, reserveOut);
        uint256 requiredIn = pool.getAmountIn(amountOut, reserveIn, reserveOut);
        // requiredIn should be >= amountIn (the +1 ceiling ensures we can afford the output).
        assertGe(requiredIn, amountIn, "getAmountIn should be >= amountIn");
        // And the diff should be at most 1 (ceiling).
        assertLe(requiredIn - amountIn, 1, "getAmountIn off by more than 1");
    }

    /// @notice Swapping token0 for token1 moves balances correctly.
    function test_SwapToken0ForToken1() public {
        // Set up pool.
        vm.startPrank(alice);
        token0.approve(address(pool), 100e18);
        token1.approve(address(pool), 100e18);
        pool.addLiquidity(100e18, 100e18, 0, 0, alice);
        vm.stopPrank();

        (uint256 r0Before, uint256 r1Before,) = pool.getReserves();

        uint256 amountIn = 1e18;
        uint256 expectedOut = pool.getAmountOut(amountIn, r0Before, r1Before);

        uint256 bobBefore1 = token1.balanceOf(bob);

        vm.startPrank(bob);
        token0.approve(address(pool), amountIn);
        uint256 out = pool.swapExactTokensForTokens(amountIn, 0, true, bob);
        vm.stopPrank();

        assertEq(out, expectedOut, "wrong amountOut returned");
        assertEq(token1.balanceOf(bob), bobBefore1 + expectedOut, "wrong token1 balance after swap");

        (uint256 r0After, uint256 r1After,) = pool.getReserves();
        assertEq(r0After, r0Before + amountIn, "reserve0 wrong after swap");
        assertEq(r1After, r1Before - expectedOut, "reserve1 wrong after swap");
    }

    /// @notice Swapping token1 for token0 moves balances correctly.
    function test_SwapToken1ForToken0() public {
        vm.startPrank(alice);
        token0.approve(address(pool), 100e18);
        token1.approve(address(pool), 100e18);
        pool.addLiquidity(100e18, 100e18, 0, 0, alice);
        vm.stopPrank();

        (uint256 r0Before, uint256 r1Before,) = pool.getReserves();

        uint256 amountIn = 1e18;
        uint256 expectedOut = pool.getAmountOut(amountIn, r1Before, r0Before);

        uint256 bobBefore0 = token0.balanceOf(bob);

        vm.startPrank(bob);
        token1.approve(address(pool), amountIn);
        uint256 out = pool.swapExactTokensForTokens(amountIn, 0, false, bob);
        vm.stopPrank();

        assertEq(out, expectedOut, "wrong amountOut");
        assertEq(token0.balanceOf(bob), bobBefore0 + expectedOut, "wrong token0 balance");

        (uint256 r0After, uint256 r1After,) = pool.getReserves();
        assertEq(r1After, r1Before + amountIn, "reserve1 wrong after swap");
        assertEq(r0After, r0Before - expectedOut, "reserve0 wrong after swap");
    }

    /// @notice K invariant is preserved (approximately) after swap.
    function test_KInvariantAfterSwap() public {
        vm.startPrank(alice);
        token0.approve(address(pool), 100e18);
        token1.approve(address(pool), 100e18);
        pool.addLiquidity(100e18, 100e18, 0, 0, alice);
        vm.stopPrank();

        (uint256 r0Before, uint256 r1Before,) = pool.getReserves();
        uint256 kBefore = r0Before * r1Before;

        vm.startPrank(bob);
        token0.approve(address(pool), 1e18);
        pool.swapExactTokensForTokens(1e18, 0, true, bob);
        vm.stopPrank();

        (uint256 r0After, uint256 r1After,) = pool.getReserves();
        uint256 kAfter = r0After * r1After;

        // k should increase (or at minimum stay the same) due to fee.
        assertGe(kAfter, kBefore, "K should not decrease after swap");
    }

    /// @notice Swap with zero amountIn reverts.
    function test_SwapZeroInputReverts() public {
        vm.startPrank(alice);
        token0.approve(address(pool), 100e18);
        token1.approve(address(pool), 100e18);
        pool.addLiquidity(100e18, 100e18, 0, 0, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(IConstantProduct.ConstantProductInsufficientInputAmount.selector);
        pool.swapExactTokensForTokens(0, 0, true, bob);
        vm.stopPrank();
    }

    /// @notice Swap that does not meet amountOutMin reverts.
    function test_SwapBelowMinOutReverts() public {
        vm.startPrank(alice);
        token0.approve(address(pool), 100e18);
        token1.approve(address(pool), 100e18);
        pool.addLiquidity(100e18, 100e18, 0, 0, alice);
        vm.stopPrank();

        (uint256 r0,,) = pool.getReserves();
        uint256 amountIn = 1e18;
        uint256 realOut = pool.getAmountOut(amountIn, r0, r0);

        vm.startPrank(bob);
        token0.approve(address(pool), amountIn);
        vm.expectRevert(IConstantProduct.ConstantProductInsufficientOutputAmount.selector);
        pool.swapExactTokensForTokens(amountIn, realOut + 1, true, bob);
        vm.stopPrank();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              VIEW / QUOTE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice getReserves reflects deposits and swaps accurately.
    function test_GetReservesReflectsState() public {
        (uint256 r0, uint256 r1, uint32 ts) = pool.getReserves();
        assertEq(r0, 0);
        assertEq(r1, 0);
        assertEq(ts, 0);

        vm.startPrank(alice);
        token0.approve(address(pool), 50e18);
        token1.approve(address(pool), 200e18);
        pool.addLiquidity(50e18, 200e18, 0, 0, alice);
        vm.stopPrank();

        (r0, r1,) = pool.getReserves();
        assertEq(r0, 50e18);
        assertEq(r1, 200e18);
    }

    /// @notice quote returns amountA * reserveB / reserveA.
    function test_QuoteCorrect() public view {
        uint256 q = pool.quote(1e18, 100e18, 400e18);
        assertEq(q, 4e18, "quote mismatch");
    }

    /// @notice getAmountOut reverts when reserveIn is zero.
    function test_GetAmountOutRevertsZeroReserveIn() public {
        vm.expectRevert(IConstantProduct.ConstantProductInsufficientLiquidity.selector);
        pool.getAmountOut(1e18, 0, 100e18);
    }

    /// @notice getAmountOut reverts when reserveOut is zero.
    function test_GetAmountOutRevertsZeroReserveOut() public {
        vm.expectRevert(IConstantProduct.ConstantProductInsufficientLiquidity.selector);
        pool.getAmountOut(1e18, 100e18, 0);
    }

    /// @notice getAmountIn reverts when amountOut >= reserveOut.
    function test_GetAmountInRevertsAmountOutGteReserveOut() public {
        vm.expectRevert(IConstantProduct.ConstantProductInsufficientLiquidity.selector);
        pool.getAmountIn(100e18, 100e18, 100e18); // amountOut == reserveOut
    }

    /// @notice quote reverts when reserveA is zero.
    function test_QuoteRevertsZeroReserveA() public {
        vm.expectRevert(IConstantProduct.ConstantProductInsufficientLiquidity.selector);
        pool.quote(1e18, 0, 100e18);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               EVENT TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice LiquidityAdded event is emitted on first deposit.
    function test_LiquidityAddedEventEmitted() public {
        uint256 a0 = 100e18;
        uint256 a1 = 400e18;
        uint256 expectedLp = 200e18 - MINIMUM_LIQUIDITY;

        vm.startPrank(alice);
        token0.approve(address(pool), a0);
        token1.approve(address(pool), a1);

        vm.expectEmit(true, true, false, true, address(pool));
        emit IConstantProduct.LiquidityAdded(alice, alice, a0, a1, expectedLp);

        pool.addLiquidity(a0, a1, 0, 0, alice);
        vm.stopPrank();
    }

    /// @notice LiquidityRemoved event is emitted on remove.
    function test_LiquidityRemovedEventEmitted() public {
        vm.startPrank(alice);
        token0.approve(address(pool), 100e18);
        token1.approve(address(pool), 400e18);
        (,, uint256 lp) = pool.addLiquidity(100e18, 400e18, 0, 0, alice);
        vm.stopPrank();

        (uint256 r0, uint256 r1,) = pool.getReserves();
        uint256 totalLp = pool.totalLpSupply();
        uint256 exp0 = (lp * r0) / totalLp;
        uint256 exp1 = (lp * r1) / totalLp;

        vm.startPrank(alice);
        vm.expectEmit(true, true, false, true, address(pool));
        emit IConstantProduct.LiquidityRemoved(alice, alice, exp0, exp1, lp);
        pool.removeLiquidity(lp, 0, 0, alice);
        vm.stopPrank();
    }

    /// @notice Swap event is emitted with correct fields.
    function test_SwapEventEmitted() public {
        vm.startPrank(alice);
        token0.approve(address(pool), 100e18);
        token1.approve(address(pool), 100e18);
        pool.addLiquidity(100e18, 100e18, 0, 0, alice);
        vm.stopPrank();

        (uint256 r0,,) = pool.getReserves();
        uint256 amountIn = 1e18;
        uint256 expectedOut = pool.getAmountOut(amountIn, r0, r0);

        vm.startPrank(bob);
        token0.approve(address(pool), amountIn);
        vm.expectEmit(true, true, false, true, address(pool));
        emit IConstantProduct.Swap(bob, bob, amountIn, 0, 0, expectedOut);
        pool.swapExactTokensForTokens(amountIn, 0, true, bob);
        vm.stopPrank();
    }

    /// @notice ReservesSync event emitted after addLiquidity.
    function test_ReservesSyncEventEmittedOnAdd() public {
        uint256 a0 = 50e18;
        uint256 a1 = 50e18;

        vm.startPrank(alice);
        token0.approve(address(pool), a0);
        token1.approve(address(pool), a1);

        vm.expectEmit(false, false, false, true, address(pool));
        emit IConstantProduct.ReservesSync(a0, a1);

        pool.addLiquidity(a0, a1, 0, 0, alice);
        vm.stopPrank();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           REENTRANCY TESTS (T1)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice A malicious ERC-20 that tries to reenter swapExactTokensForTokens
    ///         during its transfer callback must be blocked by the reentrancy guard.
    function test_SwapReentrancyReverts() public {
        // Deploy a malicious output token and a normal input token.
        MaliciousReentrantToken malToken = new MaliciousReentrantToken("MAL", "MAL");
        TestERC20 safeToken = new TestERC20("SAFE", "SAFE");

        // Build a pool where safeToken is token0 and malToken is token1 (or vice versa).
        // We need safeToken to be tokenIn (so the reentry fires on malToken transfer out).
        address t0Addr = address(safeToken) < address(malToken) ? address(safeToken) : address(malToken);
        address t1Addr = address(safeToken) < address(malToken) ? address(malToken) : address(safeToken);
        bool safeIsToken0 = (t0Addr == address(safeToken));

        ConstantProduct malPool = ConstantProduct(_deployPool(admin, t0Addr, t1Addr));

        // Seed pool — no reentry armed yet.
        safeToken.mint(alice, 200e18);
        malToken.mint(alice, 200e18);
        vm.startPrank(alice);
        safeToken.approve(address(malPool), 200e18);
        malToken.approve(address(malPool), 200e18);
        malPool.addLiquidity(100e18, 100e18, 0, 0, alice);
        vm.stopPrank();

        // Arm the malicious token: it will try to swap again during the outgoing transfer.
        malToken.setPool(address(malPool));
        // zeroForOne for the reentry attempt should be the reverse direction so
        // malToken can be the input; what matters is just that it calls back into swap.
        malToken.setZeroForOne(!safeIsToken0);

        // Bob swaps safeToken in → malToken out. During malToken.transfer(), the
        // reentry fires and must be blocked.
        safeToken.mint(bob, 10e18);
        vm.startPrank(bob);
        safeToken.approve(address(malPool), 10e18);
        // Give malToken pool balance to itself for the reentry attempt.
        vm.expectRevert(IReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        malPool.swapExactTokensForTokens(10e18, 0, safeIsToken0, bob);
        vm.stopPrank();
    }

    /// @notice A malicious token that reenters addLiquidity during transferFrom must revert.
    function test_AddLiquidityReentrancyReverts() public {
        ReentrantOnTransferFrom malToken = new ReentrantOnTransferFrom("RMAL", "RMAL");
        TestERC20 safeToken = new TestERC20("SAFE2", "SAFE2");

        address t0Addr = address(safeToken) < address(malToken) ? address(safeToken) : address(malToken);
        address t1Addr = address(safeToken) < address(malToken) ? address(malToken) : address(safeToken);

        ConstantProduct malPool = ConstantProduct(_deployPool(admin, t0Addr, t1Addr));
        malToken.setPool(address(malPool));

        safeToken.mint(alice, 200e18);
        malToken.mint(alice, 200e18);

        vm.startPrank(alice);
        safeToken.approve(address(malPool), 200e18);
        malToken.approve(address(malPool), 200e18);
        vm.expectRevert(IReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        malPool.addLiquidity(100e18, 100e18, 0, 0, alice);
        vm.stopPrank();
    }

    /// @notice A malicious token that reenters removeLiquidity during transfer must revert.
    function test_RemoveLiquidityReentrancyReverts() public {
        ReentrantOnTransfer malToken2 = new ReentrantOnTransfer("RMAL2", "RMAL2");
        TestERC20 safeToken = new TestERC20("SAFE3", "SAFE3");

        address t0Addr = address(safeToken) < address(malToken2) ? address(safeToken) : address(malToken2);
        address t1Addr = address(safeToken) < address(malToken2) ? address(malToken2) : address(safeToken);

        ConstantProduct malPool = ConstantProduct(_deployPool(admin, t0Addr, t1Addr));

        // Seed pool with honest tokens first (no reentry on first add).
        safeToken.mint(alice, 300e18);
        malToken2.mintHonest(alice, 300e18);

        vm.startPrank(alice);
        safeToken.approve(address(malPool), 200e18);
        malToken2.approve(address(malPool), 200e18);
        (,, uint256 lp) = malPool.addLiquidity(100e18, 100e18, 0, 0, alice);
        vm.stopPrank();

        // Now arm the reentry on remove.
        malToken2.setPool(address(malPool));
        malToken2.setLp(lp);

        vm.startPrank(alice);
        vm.expectRevert(IReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        malPool.removeLiquidity(lp, 0, 0, alice);
        vm.stopPrank();
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                        MALICIOUS TOKEN HELPERS
//////////////////////////////////////////////////////////////////////////*//

/// @notice Reenters swapExactTokensForTokens on transfer() (output token callback).
contract MaliciousReentrantToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    address public pool;
    bool public zeroForOne;
    bool private _inReentry;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    function setPool(address pool_) external {
        pool = pool_;
    }

    function setZeroForOne(bool z) external {
        zeroForOne = z;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        // Reenter the pool during the outgoing transfer callback.
        // Always attempt the reentry if pool is set and we're not already in one.
        if (pool != address(0) && !_inReentry) {
            _inReentry = true;
            // This reentry attempt should be blocked by the reentrancy guard.
            IConstantProduct(pool).swapExactTokensForTokens(1, 0, !zeroForOne, address(this));
            _inReentry = false;
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/// @notice Reenters addLiquidity on transferFrom() (input token callback).
contract ReentrantOnTransferFrom {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    address public pool;
    bool private _inReentry;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    function setPool(address pool_) external {
        pool = pool_;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        // Reenter addLiquidity during the transferFrom callback.
        if (pool != address(0) && !_inReentry) {
            _inReentry = true;
            IConstantProduct(pool).addLiquidity(1, 1, 0, 0, address(this));
            _inReentry = false;
        }
        return true;
    }
}

/// @notice Reenters removeLiquidity on transfer() (output token callback).
contract ReentrantOnTransfer {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    address public pool;
    uint256 public lpToRemove;
    bool private _inReentry;
    bool private _honest;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    function setPool(address pool_) external {
        pool = pool_;
    }

    function setLp(uint256 lp) external {
        lpToRemove = lp;
    }

    /// @notice Mint without triggering reentry (for seeding the pool).
    function mintHonest(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        // Reenter removeLiquidity during the outgoing transfer callback.
        if (pool != address(0) && !_inReentry && lpToRemove > 0) {
            _inReentry = true;
            IConstantProduct(pool).removeLiquidity(lpToRemove, 0, 0, address(this));
            _inReentry = false;
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
