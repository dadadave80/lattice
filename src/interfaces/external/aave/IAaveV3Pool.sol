// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAaveV3Pool
/// @author Modified from Aave v3 (https://github.com/aave/aave-v3-core/blob/master/contracts/interfaces/IPool.sol)
/// @notice Minimal vendored subset of the Aave v3 Pool used by the Lattice Aave adapter:
///         supply/withdraw (supply leg), borrow/repay/setUserEMode (leverage leg), plus the
///         account-data and reserve-data reads needed for health and aToken resolution.
/// @dev Version-pinned to Aave v3.x. Only the selectors the adapter calls are declared.
interface IAaveV3Pool {
    /// @notice Supplies `amount` of `asset` into the protocol, minting aTokens to `onBehalfOf`.
    /// @param asset       The underlying asset to supply.
    /// @param amount      The amount to supply.
    /// @param onBehalfOf  The address that receives the aTokens (the adapter).
    /// @param referralCode Unused by integrators; pass 0.
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    /// @notice Withdraws `amount` of `asset` (or the full balance with type(uint256).max) to `to`.
    /// @return withdrawn The final amount withdrawn.
    function withdraw(address asset, uint256 amount, address to) external returns (uint256 withdrawn);

    /// @notice Borrows `amount` of `asset` against the caller's collateral.
    /// @param interestRateMode 2 = variable (1 = stable, deprecated on most markets).
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
        external;

    /// @notice Repays `amount` of borrowed `asset` (type(uint256).max repays the full debt).
    /// @return repaid The final amount repaid.
    function repay(address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf)
        external
        returns (uint256 repaid);

    /// @notice Sets the caller's eMode category (e.g. correlated-asset high-LTV looping).
    function setUserEMode(uint8 categoryId) external;

    /// @notice Returns the caller's eMode category id.
    function getUserEMode(address user) external view returns (uint256);

    /// @notice Returns aggregate account data, all base-currency amounts in 8 decimals.
    /// @return totalCollateralBase     Total collateral (base ccy, 8 decimals).
    /// @return totalDebtBase           Total debt (base ccy, 8 decimals).
    /// @return availableBorrowsBase    Remaining borrow capacity (base ccy).
    /// @return currentLiquidationThreshold Weighted liquidation threshold (bps).
    /// @return ltv                     Weighted loan-to-value (bps).
    /// @return healthFactor            Position health factor (WAD, 1e18 == 1.0).
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

    /// @notice Aave v3 reserve configuration + token addresses (subset we read).
    /// @dev The full struct is large; we only consume `aTokenAddress`. Field order MUST match
    ///      the on-chain struct so ABI decoding lines up.
    struct ReserveData {
        ReserveConfigurationMap configuration;
        uint128 liquidityIndex;
        uint128 currentLiquidityRate;
        uint128 variableBorrowIndex;
        uint128 currentVariableBorrowRate;
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        uint16 id;
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint128 accruedToTreasury;
        uint128 unbacked;
        uint128 isolationModeTotalDebt;
    }

    struct ReserveConfigurationMap {
        uint256 data;
    }

    /// @notice Returns the reserve data for `asset` (used to resolve the aToken address).
    function getReserveData(address asset) external view returns (ReserveData memory);
}
