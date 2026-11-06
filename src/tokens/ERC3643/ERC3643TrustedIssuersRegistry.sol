// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC3643ClaimIssuer} from "@lattice/interfaces/external/erc3643/IERC3643ClaimIssuer.sol";
import {ITrustedIssuersRegistry} from "@lattice/interfaces/tokens/erc3643/ITrustedIssuersRegistry.sol";
import {ERC3643TrustedIssuersRegistryLib} from "@lattice/tokens/ERC3643/libraries/ERC3643TrustedIssuersRegistryLib.sol";

/// @title ERC3643TrustedIssuersRegistry
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Stateless standard TrustedIssuersRegistry facet for the closed ERC-3643 suite.
/// @custom:lattice-source ERC-3643 CC0 standard
/// @custom:lattice-requires OwnableFacet convention trusted-issuer-administration;
/// @custom:lattice-family none
/// @custom:lattice-owns none;
/// @custom:lattice-touches lattice.storage.ERC3643TrustedIssuersRegistry;
/// @custom:lattice-touches transient:lattice.storage.ERC3643Execution;
/// @custom:lattice-seam none;
/// @custom:lattice-init ERC3643Init
contract ERC3643TrustedIssuersRegistry is ITrustedIssuersRegistry {
    function addTrustedIssuer(IERC3643ClaimIssuer issuer, uint256[] calldata topics) external {
        ERC3643TrustedIssuersRegistryLib.addTrustedIssuer(issuer, topics);
    }

    function removeTrustedIssuer(IERC3643ClaimIssuer issuer) external {
        ERC3643TrustedIssuersRegistryLib.removeTrustedIssuer(issuer);
    }

    function updateIssuerClaimTopics(IERC3643ClaimIssuer issuer, uint256[] calldata topics) external {
        ERC3643TrustedIssuersRegistryLib.updateIssuerClaimTopics(issuer, topics);
    }

    function getTrustedIssuers() external view returns (IERC3643ClaimIssuer[] memory) {
        return ERC3643TrustedIssuersRegistryLib.getTrustedIssuers();
    }

    function getTrustedIssuersForClaimTopic(uint256 topic) external view returns (IERC3643ClaimIssuer[] memory) {
        return ERC3643TrustedIssuersRegistryLib.getTrustedIssuersForClaimTopic(topic);
    }

    function isTrustedIssuer(address issuer) external view returns (bool) {
        return ERC3643TrustedIssuersRegistryLib.isTrustedIssuer(issuer);
    }

    function getTrustedIssuerClaimTopics(IERC3643ClaimIssuer issuer) external view returns (uint256[] memory) {
        return ERC3643TrustedIssuersRegistryLib.getTrustedIssuerClaimTopics(issuer);
    }

    function hasClaimTopic(address issuer, uint256 topic) external view returns (bool) {
        return ERC3643TrustedIssuersRegistryLib.hasClaimTopic(issuer, topic);
    }

    /// @notice ERC-8153 packed selectors; excludes exportSelectors itself.
    function exportSelectors() external pure returns (bytes memory) {
        return hex"9f63ea98c28fb278d9dd24c552c111d134a89987ef2ed1a4b93d28eb04bc7e84";
    }
}
