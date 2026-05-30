// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InterestRate} from "@lattice/utils/libraries/InterestRate.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Harness exposing InterestRate internal functions as external calls.
contract InterestRateHarness2 {
    function getBorrowRate(InterestRate.Config memory config, uint256 util) external pure returns (uint256) {
        return InterestRate.getBorrowRate(config, util);
    }

    function getSupplyRate(InterestRate.Config memory config, uint256 util, uint256 reserveFactor)
        external
        pure
        returns (uint256)
    {
        return InterestRate.getSupplyRate(config, util, reserveFactor);
    }

    function utilization(uint256 totalBorrows, uint256 totalSupply) external pure returns (uint256) {
        return InterestRate.utilization(totalBorrows, totalSupply);
    }
}

/// @title InterestRateFuzz
contract InterestRateFuzz is Test {
    uint256 internal constant RAY = 1e27;

    InterestRateHarness2 harness;

    /// @dev Typical kinked rate config used across tests.
    InterestRate.Config internal baseConfig;

    function setUp() public {
        harness = new InterestRateHarness2();
        baseConfig = InterestRate.Config({
            baseRate: RAY / 100, // 1% pa
            slope1: 4 * RAY / 100, // 4% pa
            slope2: 75 * RAY / 100, // 75% pa
            kink: 80 * RAY / 100 // 80% utilisation kink
        });
    }

    // -------------------------------------------------------------------------
    // Borrow rate monotonicity
    // -------------------------------------------------------------------------

    /// @notice getBorrowRate is monotonically non-decreasing with utilization.
    function testFuzz_BorrowRateMonotonic(uint256 u1, uint256 u2) public view {
        // Both utilization values in [0, RAY].
        u1 = bound(u1, 0, RAY);
        u2 = bound(u2, 0, RAY);
        vm.assume(u1 < u2);

        uint256 rate1 = harness.getBorrowRate(baseConfig, u1);
        uint256 rate2 = harness.getBorrowRate(baseConfig, u2);

        assertLe(rate1, rate2, "borrow rate must be non-decreasing with utilization");
    }

    // -------------------------------------------------------------------------
    // Supply rate vs borrow rate
    // -------------------------------------------------------------------------

    /// @notice The supply rate never exceeds the borrow rate for any utilization and reserve factor.
    function testFuzz_SupplyRateNeverExceedsBorrowRate(uint256 utilization, uint256 reserveFactor) public view {
        utilization = bound(utilization, 0, RAY);
        // reserveFactor must be in [0, RAY] (validateConfig would reject > RAY).
        reserveFactor = bound(reserveFactor, 0, RAY);

        uint256 borrowRate = harness.getBorrowRate(baseConfig, utilization);
        uint256 supplyRate = harness.getSupplyRate(baseConfig, utilization, reserveFactor);

        assertLe(supplyRate, borrowRate, "supply rate must not exceed borrow rate");
    }

    // -------------------------------------------------------------------------
    // Utilization bounded
    // -------------------------------------------------------------------------

    /// @notice utilization(borrows, supply) <= RAY when borrows <= supply and supply > 0.
    function testFuzz_UtilizationBounded(uint256 borrows, uint256 supply) public view {
        // supply must be positive; borrows at most equal to supply.
        supply = bound(supply, 1, type(uint128).max);
        borrows = bound(borrows, 0, supply);

        uint256 util = harness.utilization(borrows, supply);

        assertLe(util, RAY, "utilization must be <= RAY when borrows <= supply");
    }
}
