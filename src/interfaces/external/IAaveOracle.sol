// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAaveOracle
/// @author Modified from Aave v3 (https://github.com/aave/aave-v3-core/blob/master/contracts/interfaces/IPriceOracleGetter.sol)
/// @notice Minimal vendored subset of the Aave v3 price oracle (resolved from the
///         PoolAddressesProvider via `getPriceOracle()`).
/// @dev `getAssetPrice` returns the asset price in the SAME base currency and precision that
///      `IAaveV3Pool.getUserAccountData` denominates collateral/debt in — i.e. USD with 8 decimals
///      on standard Aave v3 markets. Using this oracle to convert Aave's base-ccy account data into
///      asset units keeps the levered net-equity valuation self-consistent (no cross-oracle drift).
interface IAaveOracle {
    /// @notice Returns the price of `asset` in the protocol base currency (USD, 8 decimals).
    function getAssetPrice(address asset) external view returns (uint256);
}
