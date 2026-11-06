// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC3643ClaimIssuer} from "@lattice/interfaces/external/erc3643/IERC3643ClaimIssuer.sol";

/// @title ITrustedIssuersRegistry
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Fresh declaration of the standard CC0 ABI; implementation is authored independently.
interface ITrustedIssuersRegistry {
    error ERC3643InvalidIssuer(address issuer);
    error ERC3643IssuerAlreadyTrusted(address issuer);
    error ERC3643IssuerNotTrusted(address issuer);
    error ERC3643IssuerTopicsLength(uint256 length);
    error ERC3643TrustedIssuersLimit();

    event TrustedIssuerAdded(IERC3643ClaimIssuer indexed trustedIssuer, uint256[] claimTopics);

    event TrustedIssuerRemoved(IERC3643ClaimIssuer indexed trustedIssuer);

    event ClaimTopicsUpdated(IERC3643ClaimIssuer indexed trustedIssuer, uint256[] claimTopics);

    function addTrustedIssuer(IERC3643ClaimIssuer trustedIssuer, uint256[] calldata claimTopics) external;

    function removeTrustedIssuer(IERC3643ClaimIssuer trustedIssuer) external;

    function updateIssuerClaimTopics(IERC3643ClaimIssuer trustedIssuer, uint256[] calldata claimTopics) external;

    function getTrustedIssuers() external view returns (IERC3643ClaimIssuer[] memory);

    function getTrustedIssuersForClaimTopic(uint256 claimTopic) external view returns (IERC3643ClaimIssuer[] memory);

    function isTrustedIssuer(address issuer) external view returns (bool);

    function getTrustedIssuerClaimTopics(IERC3643ClaimIssuer trustedIssuer) external view returns (uint256[] memory);

    function hasClaimTopic(address issuer, uint256 claimTopic) external view returns (bool);
}
