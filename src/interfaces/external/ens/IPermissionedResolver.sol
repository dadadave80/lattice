// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IPermissionedResolver
/// @author Vendored minimal subset of ENSv2 PermissionedResolver (https://github.com/ensdomains/contracts-v2/blob/07e55a056f5b6a9c90119f501bdd05714e67dddd/contracts/src/resolver/PermissionedResolver.sol).
///         Upstream license: MIT.
/// @notice Permissioned, DNS-name-based address record writes.
interface IPermissionedResolver {
    function getRecordId(bytes32 node) external view returns (uint256);
    function setAddress(bytes calldata name, uint256 coinType, bytes calldata value) external;
}
