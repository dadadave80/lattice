// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IENSResolver
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ENS (https://github.com/ensdomains/ens-contracts)
/// @author Conforms to ENS forward resolution (EIP-137)
/// @notice External interface for the ENS forward-resolution facet: lets a diamond look up ENS
///         names -> addresses on-chain via the configured ENS registry.
/// @dev Read-only resolution plus a configurable registry (gated on `ENS_MANAGER_ROLE`). Basic
///      resolution only (registry -> resolver -> addr); ENSIP-10 wildcard / extended resolution is out
///      of scope for v1.
interface IENSResolver {
    /// @dev Thrown when a zero address is supplied as the ENS registry.
    error ENSResolverZeroRegistry();

    /// @dev Emitted when the configured ENS registry is set or rotated.
    /// @param ensRegistry The ENS registry address now in use.
    event EnsRegistrySet(address indexed ensRegistry);

    /// @notice Resolves an ENS `node` to its address (forward resolution).
    /// @dev Reads `registry.resolver(node)` then `resolver.addr(node)`. Returns zero ONLY when `node`
    ///      has no resolver configured; MAY revert if a configured resolver does not implement
    ///      `addr(bytes32)` or itself reverts. The resolved address is set by the node's owner (a third
    ///      party), so treat it as untrusted; use {resolverOf} to distinguish "no resolver" from "zero".
    /// @param node The ENS node (namehash) to resolve.
    /// @return The resolved address (zero if no resolver is set).
    function resolve(bytes32 node) external view returns (address);

    /// @notice Returns the resolver configured for `node` in the ENS registry.
    /// @param node The ENS node (namehash) to query.
    /// @return The resolver address (zero if unset).
    function resolverOf(bytes32 node) external view returns (address);

    /// @notice Returns the configured ENS registry.
    function ensRegistry() external view returns (address);

    /// @notice Sets or rotates the ENS registry (per-chain configuration).
    /// @dev Gated on `ENS_MANAGER_ROLE`. Reverts {ENSResolverZeroRegistry} for a zero address.
    /// @param ensRegistry The ENS registry to use.
    function setEnsRegistry(address ensRegistry) external;

    /// @notice Computes the namehash of `label`.<parent> from the parent node and label.
    /// @dev One ENS namehash recursion step: `keccak256(parentNode ++ keccak256(label))`.
    /// @param parentNode The parent name's node.
    /// @param label The subname label.
    /// @return The child node (namehash).
    function subnode(bytes32 parentNode, string calldata label) external pure returns (bytes32);
}
