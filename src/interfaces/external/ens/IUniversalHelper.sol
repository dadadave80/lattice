// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IUniversalHelper
/// @author Vendored minimal subset of ENSv2 UniversalHelper (https://github.com/ensdomains/contracts-v2/blob/07e55a056f5b6a9c90119f501bdd05714e67dddd/contracts/src/universalResolver/UniversalHelper.sol).
///         Upstream license: MIT.
/// @notice Canonical registry navigation for DNS-encoded ENS names.
interface IUniversalHelper {
    function ROOT_REGISTRY() external view returns (address);

    function findCanonicalRegistry(bytes calldata name) external view returns (address);
}
