// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IUniversalResolverV2
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Vendored minimal subset of ENS UniversalResolverV2 (https://github.com/ensdomains/contracts-v2/blob/07e55a056f5b6a9c90119f501bdd05714e67dddd/contracts/src/universalResolver/UniversalResolverV2.sol).
///         Upstream license: MIT.
/// @notice ENSv2 discovery, resolution and forward-verified reverse lookup on the canonical proxy.
interface IUniversalResolverV2 {
    function isENSv2() external view returns (bool);
    function findResolver(bytes calldata name) external view returns (address resolver, bytes32 node, uint256 offset);
    function resolve(bytes calldata name, bytes calldata data)
        external
        view
        returns (bytes memory result, address resolver);
    function reverse(bytes calldata lookupAddress, uint256 coinType)
        external
        view
        returns (string memory primary, address resolver, address reverseResolver);
}
