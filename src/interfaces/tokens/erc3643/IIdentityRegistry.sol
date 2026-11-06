// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC3643Identity} from "@lattice/interfaces/external/erc3643/IERC3643Identity.sol";
import {IClaimTopicsRegistry} from "@lattice/interfaces/tokens/erc3643/IClaimTopicsRegistry.sol";
import {IIdentityRegistryStorage} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistryStorage.sol";
import {ITrustedIssuersRegistry} from "@lattice/interfaces/tokens/erc3643/ITrustedIssuersRegistry.sol";

/// @title IIdentityRegistry
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Fresh declaration of the standard CC0 ABI; implementation is authored independently.
interface IIdentityRegistry {
    error ERC3643InvalidRegistryDependency(address dependency);
    error ERC3643UnboundIdentityStorage(address storageAddress, address registry);
    error ERC3643RegistryArrayLengths();

    event ClaimTopicsRegistrySet(address indexed claimTopicsRegistry);

    event IdentityStorageSet(address indexed identityStorage);

    event TrustedIssuersRegistrySet(address indexed trustedIssuersRegistry);

    event IdentityRegistered(address indexed investorAddress, IERC3643Identity indexed identity);

    event IdentityRemoved(address indexed investorAddress, IERC3643Identity indexed identity);

    event IdentityUpdated(IERC3643Identity indexed oldIdentity, IERC3643Identity indexed newIdentity);

    event CountryUpdated(address indexed investorAddress, uint16 indexed country);

    function registerIdentity(address userAddress, IERC3643Identity identity, uint16 country) external;

    function deleteIdentity(address userAddress) external;

    function setIdentityRegistryStorage(address identityRegistryStorage) external;

    function setClaimTopicsRegistry(address claimTopicsRegistry) external;

    function setTrustedIssuersRegistry(address trustedIssuersRegistry) external;

    function updateCountry(address userAddress, uint16 country) external;

    function updateIdentity(address userAddress, IERC3643Identity identity) external;

    function batchRegisterIdentity(
        address[] calldata userAddresses,
        IERC3643Identity[] calldata identities,
        uint16[] calldata countries
    ) external;

    function contains(address userAddress) external view returns (bool);

    function isVerified(address userAddress) external view returns (bool);

    function identity(address userAddress) external view returns (IERC3643Identity);

    function investorCountry(address userAddress) external view returns (uint16);

    function identityStorage() external view returns (IIdentityRegistryStorage);

    function issuersRegistry() external view returns (ITrustedIssuersRegistry);

    function topicsRegistry() external view returns (IClaimTopicsRegistry);
}
