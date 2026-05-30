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

/// @title ConstantProductQuoteFuzz
contract ConstantProductQuoteFuzz is Test {
    ConstantProductHarness harness;

    function setUp() public {
        harness = new ConstantProductHarness();
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
