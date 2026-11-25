// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IENSSubnameIssuerV2
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ENS (https://github.com/ensdomains/contracts-v2)
/// @notice Issues subnames in canonical ENSv2 registries that trust the caller diamond as registrar.
interface IENSSubnameIssuerV2 {
    error ENSSubnameIssuerV2InvalidHelper(address helper);
    error ENSSubnameIssuerV2AlreadyInitialized();
    error ENSSubnameIssuerV2InvalidParentName();
    error ENSSubnameIssuerV2InvalidParentRegistry(address registry);
    error ENSSubnameIssuerV2InvalidLabel();
    error ENSSubnameIssuerV2InvalidOwner();
    error ENSSubnameIssuerV2InvalidExpiry(uint64 expiry);

    event EnsUniversalHelperSet(address indexed helper);
    event EnsSubnameIssuedV2(
        address indexed parentRegistry, uint256 indexed tokenId, address indexed owner, string label
    );

    /// @notice Issues one label under the canonical registry for a normalized DNS wire parent name.
    /// @dev Requires the Lattice ENS_V2_SUBNAME_ISSUER_ROLE and an independent ENS registrar grant to this diamond.
    ///      A local issuer can act across every canonical parent that grants the diamond that external role.
    /// @param parentDnsName The DNS wire parent name. The ENS root is not a parent for this API.
    /// @param label One normalized label, prepared by the caller using ENSIP-15.
    /// @param owner The initial holder of the subname token.
    /// @param childRegistry An optional registry to attach to the issued name.
    /// @param resolver The optional resolver pointer to write on the registry.
    /// @param ownerRoles The ENSv2 role bitmap granted to the initial owner.
    /// @param expiry The future expiry as an absolute Unix timestamp.
    /// @return tokenId The registry-scoped token ID returned by ENS. It can change during the name's lifetime.
    function issueEnsSubnameV2(
        bytes calldata parentDnsName,
        string calldata label,
        address owner,
        address childRegistry,
        address resolver,
        uint256 ownerRoles,
        uint64 expiry
    ) external returns (uint256 tokenId);

    /// @notice Returns the configured ENSv2 Universal Helper.
    function ensUniversalHelper() external view returns (address);

    /// @notice Changes the trusted ENSv2 Universal Helper. Requires ENS_MANAGER_ROLE.
    function setEnsUniversalHelper(address helper) external;
}
