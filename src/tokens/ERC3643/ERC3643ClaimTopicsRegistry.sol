// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IClaimTopicsRegistry} from "@lattice/interfaces/tokens/erc3643/IClaimTopicsRegistry.sol";
import {ERC3643ClaimTopicsRegistryLib} from "@lattice/tokens/ERC3643/libraries/ERC3643ClaimTopicsRegistryLib.sol";

/// @title ERC3643ClaimTopicsRegistry
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Stateless standard ClaimTopicsRegistry facet for the closed ERC-3643 suite.
/// @custom:lattice-source ERC-3643 CC0 standard
/// @custom:lattice-requires OwnableFacet convention required-topic-administration;
/// @custom:lattice-family none
/// @custom:lattice-owns none;
/// @custom:lattice-touches lattice.storage.ERC3643ClaimTopicsRegistry;
/// @custom:lattice-touches transient:lattice.storage.ERC3643Execution;
/// @custom:lattice-seam none;
/// @custom:lattice-init ERC3643Init
contract ERC3643ClaimTopicsRegistry is IClaimTopicsRegistry {
    function addClaimTopic(uint256 topic) external {
        ERC3643ClaimTopicsRegistryLib.addClaimTopic(topic);
    }

    function removeClaimTopic(uint256 topic) external {
        ERC3643ClaimTopicsRegistryLib.removeClaimTopic(topic);
    }

    function getClaimTopics() external view returns (uint256[] memory) {
        return ERC3643ClaimTopicsRegistryLib.getClaimTopics();
    }

    /// @notice ERC-8153 packed selectors; excludes exportSelectors itself.
    function exportSelectors() external pure returns (bytes memory) {
        return hex"c7b22551df09d60408297846";
    }
}
