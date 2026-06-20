// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IENS
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Minimal vendored interface for the ENS registry, used by {ENSResolver} for forward
///         resolution. A minimal read subset: `resolver` (used for resolution) and `owner` (provided
///         for ownership checks).
/// @dev The registry address is chain-specific (the canonical registry shares one address across most
///      chains) and supplied by the deployer; it is never hardcoded here.
interface IENS {
    /// @notice Returns the resolver for `node`.
    /// @param node The ENS node (namehash) to query.
    /// @return The resolver address (zero if unset).
    function resolver(bytes32 node) external view returns (address);

    /// @notice Returns the owner of `node`.
    /// @param node The ENS node (namehash) to query.
    /// @return The owner address (zero if unset).
    function owner(bytes32 node) external view returns (address);
}
