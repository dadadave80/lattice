// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC3643Identity} from "@lattice/interfaces/external/erc3643/IERC3643Identity.sol";

/// @title IIdentityRegistryStorage
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Fresh declaration of the standard CC0 ABI; implementation is authored independently.
interface IIdentityRegistryStorage {
    error ERC3643InvalidInvestor(address wallet);
    error ERC3643InvalidIdentity(address identity);
    error ERC3643IdentityAlreadyStored(address wallet);
    error ERC3643IdentityNotStored(address wallet);
    error ERC3643UnauthorizedRegistry(address registry);
    error ERC3643InvalidRegistry(address registry);
    error ERC3643RegistryAlreadyBound(address registry);
    error ERC3643RegistryNotBound(address registry);
    error ERC3643RegistryLimit();
    error ERC3643IdentityKeyMissing(address identity, address wallet);

    event IdentityStored(address indexed investorAddress, IERC3643Identity indexed identity);

    event IdentityUnstored(address indexed investorAddress, IERC3643Identity indexed identity);

    event IdentityModified(IERC3643Identity indexed oldIdentity, IERC3643Identity indexed newIdentity);

    event CountryModified(address indexed investorAddress, uint16 indexed country);

    event IdentityRegistryBound(address indexed identityRegistry);

    event IdentityRegistryUnbound(address indexed identityRegistry);

    function addIdentityToStorage(address userAddress, IERC3643Identity identity, uint16 country) external;

    function removeIdentityFromStorage(address userAddress) external;

    function modifyStoredInvestorCountry(address userAddress, uint16 country) external;

    function modifyStoredIdentity(address userAddress, IERC3643Identity identity) external;

    function bindIdentityRegistry(address identityRegistry) external;

    function unbindIdentityRegistry(address identityRegistry) external;

    function linkedIdentityRegistries() external view returns (address[] memory);

    function storedIdentity(address userAddress) external view returns (IERC3643Identity);

    function storedInvestorCountry(address userAddress) external view returns (uint16);
}
