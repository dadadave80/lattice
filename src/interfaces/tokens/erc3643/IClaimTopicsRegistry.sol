// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IClaimTopicsRegistry
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Fresh declaration of the standard CC0 ABI; implementation is authored independently.
interface IClaimTopicsRegistry {
    error ERC3643ClaimTopicAlreadyRequired(uint256 topic);
    error ERC3643ClaimTopicNotRequired(uint256 topic);
    error ERC3643ClaimTopicsLimit();

    event ClaimTopicAdded(uint256 indexed claimTopic);

    event ClaimTopicRemoved(uint256 indexed claimTopic);

    function addClaimTopic(uint256 claimTopic) external;

    function removeClaimTopic(uint256 claimTopic) external;

    function getClaimTopics() external view returns (uint256[] memory);
}
