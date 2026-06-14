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

    /// @notice Returns the address of the price oracle (Aave's own; unused for valuation —
    ///         Lattice prices net equity via its own oracle).
    function getPriceOracle() external view returns (address);
}
