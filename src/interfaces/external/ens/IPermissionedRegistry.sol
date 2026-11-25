// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IPermissionedRegistry
/// @author Vendored minimal subset of ENSv2 IPermissionedRegistry via IStandardRegistry (https://github.com/ensdomains/contracts-v2/blob/07e55a056f5b6a9c90119f501bdd05714e67dddd/contracts/src/registry/interfaces/IStandardRegistry.sol).
///         Upstream license: MIT.
/// @notice Registration surface of an ENSv2 permissioned registry.
interface IPermissionedRegistry {
    function register(
        string calldata label,
        address owner,
        address registry,
        address resolver,
        uint256 roleBitmap,
        uint64 expiry
    ) external returns (uint256 tokenId);
}
