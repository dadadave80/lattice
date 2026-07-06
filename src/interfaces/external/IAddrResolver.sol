// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAddrResolver
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Vendored minimal subset of ENS's `IAddrResolver` (https://github.com/ensdomains/ens-contracts). Upstream is MIT.
/// @notice Minimal vendored interface for an ENS address resolver (EIP-137 `addr`), used by
///         {ENSResolver} for forward resolution.
interface IAddrResolver {
    /// @notice Returns the address associated with an ENS `node`.
    /// @param node The ENS node (namehash) to resolve.
    /// @return The associated address (zero if unset).
    function addr(bytes32 node) external view returns (address payable);
}
