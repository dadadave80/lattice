// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InterestRate} from "@lattice/utils/libraries/InterestRate.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Thin harness that exposes InterestRate's internal functions.
contract InterestRateHarness {
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

    function validateConfig(InterestRate.Config memory config) external pure {
        InterestRate.validateConfig(config);
    }
}

/// @title InterestRateTest
/// @notice Tests for the InterestRate utility library.
contract InterestRateTest is Test {
    uint256 internal constant RAY = 1e27;

    InterestRateHarness internal harness;

    /// @dev Typical Aave/Compound-like parameters:
    ///      baseRate = 1% per year, slope1 = 4% per year (below 80% kink),
    ///      slope2 = 75% per year (above kink), kink = 80%.
    InterestRate.Config internal defaultConfig;

    function setUp() public {
        harness = new InterestRateHarness();
        defaultConfig = InterestRate.Config({
            baseRate: RAY / 100, // 1%
            slope1: 4 * RAY / 100, // 4%
            slope2: 75 * RAY / 100, // 75%
            kink: 80 * RAY / 100 // 80%
        });
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         BORROW RATE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice At 0% utilization, borrow rate equals baseRate.
    function test_BorrowRate_ZeroUtilization() public view {
        uint256 rate = harness.getBorrowRate(defaultConfig, 0);
        assertEq(rate, defaultConfig.baseRate, "rate at 0% should be baseRate");
    }

    /// @notice At exactly the kink, borrow rate equals baseRate + slope1.
    function test_BorrowRate_AtKink() public view {
        uint256 rate = harness.getBorrowRate(defaultConfig, defaultConfig.kink);
        assertEq(rate, defaultConfig.baseRate + defaultConfig.slope1, "rate at kink should be baseRate + slope1");
    }

    /// @notice Below the kink, rate is a linear interpolation on slope1.
    function test_BorrowRate_BelowKink_Linear() public view {
        // 40% utilization = half of 80% kink => rate = baseRate + slope1 / 2
        uint256 util = 40 * RAY / 100;
        uint256 rate = harness.getBorrowRate(defaultConfig, util);
        uint256 expected = defaultConfig.baseRate + (util * defaultConfig.slope1) / defaultConfig.kink;
        assertEq(rate, expected, "below-kink rate should be linear in slope1");
    }

    /// @notice Above the kink, the second slope kicks in.
    function test_BorrowRate_AboveKink() public view {
        // 90% utilization: excess = 10%, remaining range = 20%
        uint256 util = 90 * RAY / 100;
        uint256 rate = harness.getBorrowRate(defaultConfig, util);
        uint256 excess = util - defaultConfig.kink; // 10%
        uint256 remaining = RAY - defaultConfig.kink; // 20%
        uint256 expected = defaultConfig.baseRate + defaultConfig.slope1 + (excess * defaultConfig.slope2) / remaining;
        assertEq(rate, expected, "above-kink rate should use slope2");
    }

    /// @notice At 100% utilization, borrow rate = baseRate + slope1 + slope2.
    function test_BorrowRate_FullUtilization() public view {
        uint256 rate = harness.getBorrowRate(defaultConfig, RAY);
        uint256 expected = defaultConfig.baseRate + defaultConfig.slope1 + defaultConfig.slope2;
        assertEq(rate, expected, "rate at 100% should be baseRate + slope1 + slope2");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         SUPPLY RATE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Supply rate with zero reserve factor returns borrowRate * utilization / RAY.
    function test_SupplyRate_ZeroReserveFactor() public view {
        uint256 util = 50 * RAY / 100; // 50%
        uint256 reserveFactor = 0;
        uint256 supplyRate = harness.getSupplyRate(defaultConfig, util, reserveFactor);
        uint256 borrowRate = harness.getBorrowRate(defaultConfig, util);
        // supplyRate = borrowRate * util / RAY * (RAY - 0) / RAY = borrowRate * util / RAY
        uint256 expected = (borrowRate * util / RAY);
        assertEq(supplyRate, expected, "supply rate should equal borrowRate * util / RAY when reserveFactor=0");
    }

    /// @notice Supply rate with 10% reserve factor matches manual calculation.
    function test_SupplyRate_WithReserveFactor() public view {
        uint256 util = 80 * RAY / 100; // at kink
        uint256 reserveFactor = RAY / 10; // 10%
        uint256 supplyRate = harness.getSupplyRate(defaultConfig, util, reserveFactor);
        uint256 borrowRate = harness.getBorrowRate(defaultConfig, util);
        // step1 = borrowRate * util / RAY
        uint256 step1 = borrowRate * util / RAY;
        // step2 = step1 * (RAY - reserveFactor) / RAY
        uint256 expected = step1 * (RAY - reserveFactor) / RAY;
        assertEq(supplyRate, expected, "supply rate should match manual calc with reserve factor");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         UTILIZATION HELPER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Utilization is 0 when total supply is 0.
    function test_Utilization_ZeroSupply() public view {
        assertEq(harness.utilization(0, 0), 0, "utilization should be 0 when supply is 0");
        assertEq(harness.utilization(100, 0), 0, "utilization should be 0 when supply is 0 (borrows > 0)");
    }

    /// @notice Utilization at 100% when borrows == supply.
    function test_Utilization_FullUtilization() public view {
        uint256 amount = 1e18;
        assertEq(harness.utilization(amount, amount), RAY, "utilization should be RAY when borrows == supply");
    }

    /// @notice Utilization at 50% when borrows == supply / 2.
    function test_Utilization_HalfUtilization() public view {
        uint256 supply = 2e18;
        uint256 borrows = 1e18;
        assertEq(harness.utilization(borrows, supply), RAY / 2, "utilization should be 50%");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         CONFIG VALIDATION TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Valid config does not revert.
    function test_ValidateConfig_Valid() public view {
        harness.validateConfig(defaultConfig); // should not revert
    }

    /// @notice Config with kink > RAY reverts with InvalidConfig.
    function test_ValidateConfig_KinkAboveRay_Reverts() public {
        InterestRate.Config memory bad = InterestRate.Config({baseRate: 0, slope1: 0, slope2: 0, kink: RAY + 1});
        vm.expectRevert(InterestRate.InvalidConfig.selector);
        harness.validateConfig(bad);
    }

    /// @notice Config with kink == 0 reverts with InvalidConfig.
    function test_ValidateConfig_KinkZero_Reverts() public {
        InterestRate.Config memory bad = InterestRate.Config({baseRate: 0, slope1: 0, slope2: 0, kink: 0});
        vm.expectRevert(InterestRate.InvalidConfig.selector);
        harness.validateConfig(bad);
    }

    /// @notice Config with kink == RAY is valid (100% kink, only slope1 ever applies).
    function test_ValidateConfig_KinkEqualRay() public view {
        InterestRate.Config memory cfg = InterestRate.Config({baseRate: 0, slope1: RAY / 10, slope2: 0, kink: RAY});
        harness.validateConfig(cfg); // should not revert
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         FUZZ TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Borrow rate is monotonically non-decreasing with utilization.
    function testFuzz_BorrowRate_Monotonic(uint256 u1, uint256 u2) public view {
        u1 = bound(u1, 0, RAY);
        u2 = bound(u2, u1, RAY);
        uint256 r1 = harness.getBorrowRate(defaultConfig, u1);
        uint256 r2 = harness.getBorrowRate(defaultConfig, u2);
        assertGe(r2, r1, "borrow rate must be monotonically non-decreasing");
    }

    /// @notice Supply rate is always <= borrow rate (lenders can only earn <= borrowers pay).
    function testFuzz_SupplyRate_LteoBorrowRate(uint256 util, uint256 reserveFactor) public view {
        util = bound(util, 0, RAY);
        reserveFactor = bound(reserveFactor, 0, RAY);
        uint256 supplyRate = harness.getSupplyRate(defaultConfig, util, reserveFactor);
        uint256 borrowRate = harness.getBorrowRate(defaultConfig, util);
        assertLe(supplyRate, borrowRate, "supply rate must be <= borrow rate");
    }
}
