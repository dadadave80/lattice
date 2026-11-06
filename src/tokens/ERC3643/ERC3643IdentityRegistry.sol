// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC3643Identity} from "@lattice/interfaces/external/erc3643/IERC3643Identity.sol";
import {IClaimTopicsRegistry} from "@lattice/interfaces/tokens/erc3643/IClaimTopicsRegistry.sol";
import {IIdentityRegistry} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistry.sol";
import {IIdentityRegistryStorage} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistryStorage.sol";
import {ITrustedIssuersRegistry} from "@lattice/interfaces/tokens/erc3643/ITrustedIssuersRegistry.sol";
import {ERC3643IdentityRegistryLib} from "@lattice/tokens/ERC3643/libraries/ERC3643IdentityRegistryLib.sol";

/// @title ERC3643IdentityRegistry
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Stateless standard IdentityRegistry facet for the closed ERC-3643 suite.
/// @custom:lattice-source ERC-3643 CC0 standard
/// @custom:lattice-requires OwnableFacet convention identity-dependency-administration;
/// @custom:lattice-requires ERC3643AgentRole convention investor-administration;
/// @custom:lattice-requires ERC3643IdentityRegistryStorage convention identity-storage-administration;
/// @custom:lattice-requires ERC3643TrustedIssuersRegistry convention issuer-administration;
/// @custom:lattice-requires ERC3643ClaimTopicsRegistry convention topic-administration;
/// @custom:lattice-family none
/// @custom:lattice-owns none;
/// @custom:lattice-touches lattice.storage.ERC3643IdentityRegistry;
/// @custom:lattice-touches lattice.storage.ERC3643IdentityRegistryStorage;
/// @custom:lattice-touches transient:lattice.storage.ERC3643Execution;
/// @custom:lattice-seam none;
/// @custom:lattice-init ERC3643Init
contract ERC3643IdentityRegistry is IIdentityRegistry {
    function setIdentityRegistryStorage(address endpoint) external {
        ERC3643IdentityRegistryLib.setIdentityRegistryStorage(endpoint);
    }

    function setTrustedIssuersRegistry(address endpoint) external {
        ERC3643IdentityRegistryLib.setTrustedIssuersRegistry(endpoint);
    }

    function setClaimTopicsRegistry(address endpoint) external {
        ERC3643IdentityRegistryLib.setClaimTopicsRegistry(endpoint);
    }

    function identityStorage() external view returns (IIdentityRegistryStorage) {
        return ERC3643IdentityRegistryLib.identityStorage();
    }

    function issuersRegistry() external view returns (ITrustedIssuersRegistry) {
        return ERC3643IdentityRegistryLib.issuersRegistry();
    }

    function topicsRegistry() external view returns (IClaimTopicsRegistry) {
        return ERC3643IdentityRegistryLib.topicsRegistry();
    }

    function registerIdentity(address wallet, IERC3643Identity investorIdentity, uint16 country) external {
        ERC3643IdentityRegistryLib.registerIdentity(wallet, investorIdentity, country);
    }

    function deleteIdentity(address wallet) external {
        ERC3643IdentityRegistryLib.deleteIdentity(wallet);
    }

    function updateCountry(address wallet, uint16 country) external {
        ERC3643IdentityRegistryLib.updateCountry(wallet, country);
    }

    function updateIdentity(address wallet, IERC3643Identity investorIdentity) external {
        ERC3643IdentityRegistryLib.updateIdentity(wallet, investorIdentity);
    }

    function batchRegisterIdentity(
        address[] calldata wallets,
        IERC3643Identity[] calldata identities,
        uint16[] calldata countries
    ) external {
        ERC3643IdentityRegistryLib.batchRegisterIdentity(wallets, identities, countries);
    }

    function identity(address wallet) external view returns (IERC3643Identity) {
        return ERC3643IdentityRegistryLib.identity(wallet);
    }

    function investorCountry(address wallet) external view returns (uint16) {
        return ERC3643IdentityRegistryLib.investorCountry(wallet);
    }

    function contains(address wallet) external view returns (bool) {
        return ERC3643IdentityRegistryLib.contains(wallet);
    }

    function isVerified(address wallet) external view returns (bool) {
        return ERC3643IdentityRegistryLib.isVerified(wallet);
    }

    /// @notice ERC-8153 packed selectors; excludes exportSelectors itself.
    function exportSelectors() external pure returns (bytes memory) {
        return hex"653dc9f15dbe47e8a8d29d1df0eb5e54f11abfd87e42683bb9209e33b4f3fcb7454a03e0670af6a926d941aee744d7893b3e12f43b239a7f8e098ca1";
    }
}
