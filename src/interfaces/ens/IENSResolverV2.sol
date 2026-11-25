// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IENSResolverV2
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ENS Universal Resolver (https://github.com/ensdomains/contracts-v2)
/// @notice Reads synchronous ETH records through the configured ENSv2 Universal Resolver.
interface IENSResolverV2 {
    /// @dev The endpoint must have code and identify itself as ENSv2.
    error InvalidENSUniversalResolver(address endpoint);
    /// @dev This module's storage has already been initialized in this diamond.
    error ENSResolverV2AlreadyInitialized();
    /// @dev Rotation requires a completed module initialization.
    error ENSResolverV2NotInitialized();
    /// @dev The ETH address record returned a noncanonical ABI address.
    error InvalidENSAddressResult();
    /// @dev A client must query the proxy directly with ERC-3668 enabled to retrieve this record.
    error ENSOffchainLookupRequired(address universalResolver);
    /// @notice Emitted when initialization or the manager configures the resolver proxy.
    event EnsUniversalResolverSet(address indexed universalResolver);

    /// @notice Reads the ETH address for a normalized DNS wire-format name.
    /// @dev Normalize the name before encoding. A zero record returns zero. Discovery, missing resolver
    ///      and record errors propagate. Off-chain records revert with ENSOffchainLookupRequired.
    function resolveEnsAddressV2(bytes calldata dnsName) external view returns (address);
    /// @notice The configured Universal Resolver proxy.
    function ensUniversalResolver() external view returns (address);
    /// @notice Rotates the proxy. An ENS_MANAGER_ROLE holder thereby controls future resolution answers.
    function setEnsUniversalResolver(address universalResolver) external;
}
