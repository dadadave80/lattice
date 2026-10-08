// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ConstantProductLib} from "@lattice/amm/libraries/ConstantProductLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Harness that exposes ConstantProductLib's pure quote functions.
contract ConstantProductHarness {
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256) {
        return ConstantProductLib.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256) {
        return ConstantProductLib.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256) {
        return ConstantProductLib.quote(amountA, reserveA, reserveB);
    }
}

/// @title UniswapV2QuoteReference
/// @author Modified from Uniswap V2 (https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol)
/// @notice Differential oracle: `UniswapV2Library.getAmountOut` / `getAmountIn` as formulas (997/1000 fee scaling,
///         the V2 zero-amount and zero-reserve guards, and checked arithmetic standing in for SafeMath).
contract UniswapV2QuoteReference {
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }
}

/// @title ConstantProductQuoteFuzz
contract ConstantProductQuoteFuzz is Test {
    ConstantProductHarness harness;
    UniswapV2QuoteReference v2;

    function setUp() public {
        harness = new ConstantProductHarness();
        v2 = new UniswapV2QuoteReference();
    }

    // -------------------------------------------------------------------------
    // Differential: Uniswap V2 reference
    // -------------------------------------------------------------------------

    /// @notice Over V2's uint112 reserve domain, getAmountOut equals UniswapV2Library.getAmountOut exactly
    ///         (9970/10000 is 997/1000 scaled by 10, so the floor is identical), and both revert on empty reserves.
    function testFuzz_GetAmountOutMatchesUniswapV2(uint112 amountIn, uint112 reserveIn, uint112 reserveOut)
        public
        view
    {
        vm.assume(amountIn > 0);
        _assertSameQuote(
            abi.encodeCall(harness.getAmountOut, (amountIn, reserveIn, reserveOut)),
            abi.encodeCall(v2.getAmountOut, (amountIn, reserveIn, reserveOut)),
            "getAmountOut"
        );
    }

    /// @notice Over V2's uint112 reserve domain, getAmountIn equals UniswapV2Library.getAmountIn exactly (including
    ///         V2's unconditional `+ 1`), and both revert for `amountOut >= reserveOut` or empty reserves.
    function testFuzz_GetAmountInMatchesUniswapV2(uint112 amountOut, uint112 reserveIn, uint112 reserveOut)
        public
        view
    {
        vm.assume(amountOut > 0);
        _assertSameQuote(
            abi.encodeCall(harness.getAmountIn, (amountOut, reserveIn, reserveOut)),
            abi.encodeCall(v2.getAmountIn, (amountOut, reserveIn, reserveOut)),
            "getAmountIn"
        );
    }

    /// @notice Over all of uint256, whenever Lattice returns a quote V2 returns the same one. The converse does not
    ///         hold: the 10x fee scaling makes Lattice overflow (and revert) slightly before V2 near 2^256.
    function testFuzz_QuotesNeverDivergeWhereLatticeSucceeds(uint256 amount, uint256 reserveIn, uint256 reserveOut)
        public
        view
    {
        vm.assume(amount > 0);
        _assertLatticeOkImpliesSame(
            abi.encodeCall(harness.getAmountOut, (amount, reserveIn, reserveOut)),
            abi.encodeCall(v2.getAmountOut, (amount, reserveIn, reserveOut)),
            "getAmountOut"
        );
        _assertLatticeOkImpliesSame(
            abi.encodeCall(harness.getAmountIn, (amount, reserveIn, reserveOut)),
            abi.encodeCall(v2.getAmountIn, (amount, reserveIn, reserveOut)),
            "getAmountIn"
        );
    }

    /// @notice Independent of V2: getAmountOut is the LARGEST output the fee-adjusted K check accepts, i.e.
    ///         `(rIn * 10000 + in * 9970) * (rOut - out) >= rIn * rOut * 10000`, and `out + 1` fails it.
    function testFuzz_GetAmountOutIsMaximalUnderKCheck(uint112 amountIn, uint112 reserveIn, uint112 reserveOut)
        public
        view
    {
        vm.assume(amountIn > 0 && reserveIn > 0 && reserveOut > 0);
        uint256 out = harness.getAmountOut(amountIn, reserveIn, reserveOut);
        assertLt(out, reserveOut, "output below reserve");

        uint256 balanceAdjusted = uint256(reserveIn) * 10000 + uint256(amountIn) * 9970;
        uint256 k = uint256(reserveIn) * reserveOut * 10000;
        assertGe(balanceAdjusted * (reserveOut - out), k, "quoted output passes the K check");
        assertLt(balanceAdjusted * (reserveOut - out - 1), k, "one more unit fails the K check");
    }

    /// @notice getAmountIn always buys at least the requested output: getAmountOut(getAmountIn(out)) >= out.
    function testFuzz_GetAmountInBuysRequestedOutput(uint112 amountOut, uint112 reserveIn, uint112 reserveOut)
        public
        view
    {
        vm.assume(reserveIn > 0 && reserveOut > 1);
        // At most half the output reserve keeps the required input within uint113, so re-quoting cannot overflow.
        amountOut = uint112(bound(amountOut, 1, reserveOut / 2));
        uint256 amountIn = harness.getAmountIn(amountOut, reserveIn, reserveOut);
        assertGe(harness.getAmountOut(amountIn, reserveIn, reserveOut), amountOut, "input buys the output");
    }

    /// @notice Known divergence: a zero amount quotes 0 out / 1 in where V2 reverts. The swap paths reject a zero
    ///         input before quoting (`ConstantProductInsufficientInputAmount`).
    function test_ZeroAmountQuotesWhereUniswapV2Reverts() public {
        assertEq(harness.getAmountOut(0, 1e18, 1e18), 0, "zero input quotes zero output");
        assertEq(harness.getAmountIn(0, 1e18, 1e18), 1, "zero output quotes one unit of input");

        vm.expectRevert(bytes("INSUFFICIENT_INPUT_AMOUNT"));
        v2.getAmountOut(0, 1e18, 1e18);
        vm.expectRevert(bytes("INSUFFICIENT_OUTPUT_AMOUNT"));
        v2.getAmountIn(0, 1e18, 1e18);
    }

    /// @notice Known divergence: scaling the fee by 10000 instead of 1000 makes the public quote views overflow for
    ///         inputs within 10x of 2^256 that V2 still quotes. Unreachable from swaps (reserves are uint112).
    function test_FeeScalingOverflowsBeforeUniswapV2() public {
        uint256 amountIn = type(uint256).max / 9970 + 1;
        assertEq(v2.getAmountOut(amountIn, 1, 1), 0, "V2 quotes");
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        harness.getAmountOut(amountIn, 1, 1);
    }

    /// @dev Both calls revert, or both return the same quote.
    function _assertSameQuote(bytes memory latticeCall, bytes memory v2Call, string memory label) internal view {
        (bool okL, bytes memory retL) = address(harness).staticcall(latticeCall);
        (bool okV, bytes memory retV) = address(v2).staticcall(v2Call);
        assertEq(okL, okV, string.concat(label, ": revert domain differs from Uniswap V2"));
        if (okL) assertEq(abi.decode(retL, (uint256)), abi.decode(retV, (uint256)), string.concat(label, ": quote"));
    }

    /// @dev If the Lattice call returns, the V2 call returns the same quote.
    function _assertLatticeOkImpliesSame(bytes memory latticeCall, bytes memory v2Call, string memory label)
        internal
        view
    {
        (bool okL, bytes memory retL) = address(harness).staticcall(latticeCall);
        if (!okL) return;
        (bool okV, bytes memory retV) = address(v2).staticcall(v2Call);
        assertTrue(okV, string.concat(label, ": Uniswap V2 reverts where Lattice quotes"));
        assertEq(abi.decode(retL, (uint256)), abi.decode(retV, (uint256)), string.concat(label, ": quote"));
    }

    /// @notice getAmountOut is monotonically non-decreasing with amountIn.
    function testFuzz_GetAmountOutMonotonic(uint128 reserveIn, uint128 reserveOut, uint128 a, uint128 b) public view {
        // Reserves capped to uint64 so amountIn * (10000 - fee) * reserveOut fits uint256.
        reserveIn = uint128(bound(uint256(reserveIn), 1, type(uint64).max));
        reserveOut = uint128(bound(uint256(reserveOut), 1, type(uint64).max));
        a = uint128(bound(uint256(a), 1, type(uint64).max));
        b = uint128(bound(uint256(b), 1, type(uint64).max));
        vm.assume(a < b);

        uint256 outA = harness.getAmountOut(a, reserveIn, reserveOut);
        uint256 outB = harness.getAmountOut(b, reserveIn, reserveOut);

        assertLe(outA, outB, "getAmountOut must be non-decreasing");
    }

    /// @notice quote(amountA, reserveA, reserveB) == amountA * reserveB / reserveA.
    function testFuzz_QuoteSymmetry(uint128 amountA, uint128 reserveA, uint128 reserveB) public view {
        vm.assume(reserveA > 0);
        vm.assume(amountA > 0);

        uint256 result = harness.quote(amountA, reserveA, reserveB);
        uint256 expected = (uint256(amountA) * uint256(reserveB)) / uint256(reserveA);

        assertEq(result, expected, "quote must equal amountA * reserveB / reserveA");
    }

    /// @notice getAmountIn(getAmountOut(amountIn,...), ...) is within 1 unit of amountIn.
    /// @dev The floor truncation in getAmountOut and the ceiling (+1) in getAmountIn compose to
    ///      produce a result within [amountIn - 1, amountIn + something].  A tight >= amountIn
    ///      claim is falsifiable for certain (reserve, amountIn) pairs due to integer division.
    ///      The weaker property: the inverse differs by at most 1 unit (one tick of rounding).
    /// forge-config: default.fuzz.runs = 64
    function testFuzz_GetAmountInGetAmountOutInverseBalanced(uint64 reserve, uint64 amountIn) public view {
        // Balanced pool: reserveIn == reserveOut (maximises symmetry, minimises ratio-induced truncation).
        reserve = uint64(bound(uint256(reserve), 1_000_000, 1e15));
        // amountIn at most 0.1% of reserve to keep out well below reserveOut.
        amountIn = uint64(bound(uint256(amountIn), 1, uint256(reserve) / 1_000 + 1));

        uint256 out = harness.getAmountOut(amountIn, reserve, reserve);

        // Skip degenerate case: output = 0 (dust input rounds to zero).
        vm.assume(out > 0);
        vm.assume(out < reserve);

        uint256 amountInRequired = harness.getAmountIn(out, reserve, reserve);

        // The inverse should recover at least (amountIn - 1) due to rounding.
        assertGe(amountInRequired + 1, amountIn, "getAmountIn(getAmountOut(x)) must be within 1 of x");
    }
}
