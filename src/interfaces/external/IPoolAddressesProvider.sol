// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IPoolAddressesProvider
/// @author Modified from Aave v3 (https://github.com/aave/aave-v3-core/blob/master/contracts/interfaces/IPoolAddressesProvider.sol)
/// @notice Minimal vendored subset: resolves the current Pool proxy address.
/// @dev Adapters re-resolve `getPool()` on every state-changing call so an Aave proxy upgrade
///      is picked up automatically and approvals are always granted to the live Pool.
interface IPoolAddressesProvider {
    /// @notice Returns the address of the Pool proxy.
    function getPool() external view returns (address);

    /// @notice Returns the address of Aave's own price oracle (`IAaveOracle`). Used by the adapter to
    ///         convert Aave's base-ccy account data into asset units with a single self-consistent
    ///         price source (no cross-oracle divergence with the levered net-equity valuation).
    function getPriceOracle() external view returns (address);
}
