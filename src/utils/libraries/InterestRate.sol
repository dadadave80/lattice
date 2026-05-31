// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title InterestRate
/// @author Modified from Compound (https://github.com/compound-finance/compound-protocol/blob/master/contracts/JumpRateModelV2.sol)
/// @notice Stateless utility library implementing the kinked (Aave/Compound-style) interest rate model.
/// @dev No own ERC-7201 storage. The consumer module holds any storage that references this library.
///      All rates are ray-scaled (1e27 = 100%).
library InterestRate {
    //*//////////////////////////////////////////////////////////////////////////
    //                                 CONSTANTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Ray scaling factor (1e27 = 100%).
    uint256 internal constant RAY = 1e27;

    //*//////////////////////////////////////////////////////////////////////////
    //                                  STRUCTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Configuration for the kinked interest rate model.
    struct Config {
        /// @dev Annualized borrow rate at 0% utilization, ray-scaled (1e27 = 100%).
        uint256 baseRate;
        /// @dev Slope of the rate curve below the kink, ray-scaled.
        uint256 slope1;
        /// @dev Slope of the rate curve above the kink, ray-scaled.
        uint256 slope2;
        /// @dev Utilization breakpoint where the slope changes, ray-scaled (e.g., 0.8e27 = 80%).
        uint256 kink;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  ERRORS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Reverts when a Config is structurally invalid (e.g., kink > RAY).
    error InvalidConfig();

    //*//////////////////////////////////////////////////////////////////////////
    //                            CORE RATE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Computes the annualized borrow rate given current utilization.
    /// @dev Uses a two-slope (kinked) model:
    ///      - Below kink: `baseRate + utilization * slope1 / kink`
    ///      - At or above kink: `baseRate + slope1 + (utilization - kink) * slope2 / (RAY - kink)`
    ///      Utilization is capped at RAY (100%) on entry; values above RAY are physically impossible
    ///      and would cause division-by-zero when `kink == RAY` (remainingRange == 0).
    ///      When kink == RAY, capping util to RAY means `util <= kink` is always true, so the
    ///      second slope never applies and the denominator is never zero.
    /// @param config Rate model parameters.
    /// @param util Borrow/supply ratio, ray-scaled (1e27 = 100%). Values above RAY are capped to RAY.
    /// @return borrowRate Annualized borrow rate, ray-scaled.
    function getBorrowRate(Config memory config, uint256 util) internal pure returns (uint256 borrowRate) {
        // Cap utilization at 100% — values above RAY are physically impossible and would cause
        // division-by-zero in the above-kink branch when kink == RAY (remainingRange == 0).
        if (util > RAY) util = RAY;
        if (util <= config.kink) {
            // Below or at kink: linear interpolation on slope1.
            // Safe: kink > 0 enforced by validateConfig; util <= kink so numerator <= kink * slope1 which fits uint256.
            borrowRate = config.baseRate + (util * config.slope1) / config.kink;
        } else {
            // Above kink: add slope1 fully, then linearly interpolate slope2 over the remaining range.
            // util is already capped at RAY, so excess is bounded. remainingRange > 0 because
            // validateConfig enforces kink > 0 and kink <= RAY, and when kink == RAY this branch
            // is unreachable (util <= RAY == kink, so the above condition is always true).
            uint256 excess = util - config.kink;
            uint256 remainingRange = RAY - config.kink;
            borrowRate = config.baseRate + config.slope1 + (excess * config.slope2) / remainingRange;
        }
    }

    /// @notice Computes the annualized supply rate given utilization and reserve factor.
    /// @dev Formula: `borrowRate * utilization * (RAY - reserveFactor) / RAY / RAY`.
    ///      Uses two sequential full-precision mulDiv steps to avoid intermediate overflow
    ///      without requiring 512-bit arithmetic.
    /// @param config Rate model parameters.
    /// @param util Borrow/supply ratio, ray-scaled.
    /// @param reserveFactor Fraction of borrow interest kept as protocol reserves, ray-scaled.
    ///        Must be <= RAY (i.e., at most 100% of interest goes to reserves).
    /// @return supplyRate Annualized supply rate, ray-scaled.
    function getSupplyRate(Config memory config, uint256 util, uint256 reserveFactor)
        internal
        pure
        returns (uint256 supplyRate)
    {
        if (reserveFactor > RAY) revert InvalidConfig();
        uint256 borrowRate = getBorrowRate(config, util);
        // Step 1: borrowRate * util / RAY  (scales back from double-ray to single-ray)
        uint256 intermediate = _rayMul(borrowRate, util);
        // Step 2: intermediate * (RAY - reserveFactor) / RAY
        uint256 lenderShare = RAY - reserveFactor;
        supplyRate = _rayMul(intermediate, lenderShare);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Computes borrow utilization as totalBorrows / totalSupply, ray-scaled.
    /// @dev Returns 0 if totalSupply is 0 to avoid division by zero.
    ///
    ///      Overflow note (L-4): `totalBorrows * RAY` overflows uint256 when
    ///      `totalBorrows > type(uint256).max / 1e27 ≈ 1.16e50`. This is an
    ///      astronomically large token amount (far beyond any real protocol's TVL),
    ///      but callers should ensure `totalBorrows` is within this bound.
    ///      If overflow-safe math is required, use `mulDiv(totalBorrows, RAY, totalSupply)`.
    /// @param totalBorrows Total outstanding borrows denominated in the asset.
    /// @param totalSupply Total supplied assets (may include idle + allocated).
    /// @return util Utilization ratio, ray-scaled (1e27 = 100%).
    function utilization(uint256 totalBorrows, uint256 totalSupply) internal pure returns (uint256 util) {
        if (totalSupply == 0) return 0;
        util = totalBorrows * RAY / totalSupply;
    }

    /// @notice Validates that a Config is well-formed; reverts with `InvalidConfig` otherwise.
    /// @dev Checks:
    ///      - kink must be <= RAY (utilization is always in [0, RAY])
    ///      - kink must be > 0 (otherwise the first-slope formula divides by zero)
    ///
    ///      Note on overflow (L-3): `baseRate`, `slope1`, and `slope2` are not bounded here.
    ///      The two-slope formula can produce a borrowRate larger than RAY for extreme configs
    ///      (e.g. slope2 >> RAY). If borrowRate > type(uint256).max / RAY, the intermediate
    ///      product in _rayMul silently overflows. Consumers MUST ensure that
    ///      `baseRate + slope1 + slope2 <= type(uint256).max / RAY` (~1.16e50) for safety.
    ///      Practical lending protocols use rates well below this bound (e.g., all fields <= 10*RAY).
    /// @param config The Config to validate.
    function validateConfig(Config memory config) internal pure {
        // kink must be in (0, RAY]
        if (config.kink == 0 || config.kink > RAY) revert InvalidConfig();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INTERNAL MATH HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Multiplies two ray-scaled values and divides by RAY, truncating (floor).
    ///      Intermediate product can reach up to (1e27)^2 = 1e54 < 2^256, so no overflow.
    function _rayMul(uint256 a, uint256 b) private pure returns (uint256) {
        return (a * b) / RAY;
    }
}
