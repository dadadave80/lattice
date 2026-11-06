// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {IClaimTopicsRegistry} from "@lattice/interfaces/tokens/erc3643/IClaimTopicsRegistry.sol";
import {ERC3643ExecutionLib} from "@lattice/tokens/ERC3643/libraries/ERC3643ExecutionLib.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC3643ClaimTopicsRegistry")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC3643_CLAIM_TOPICS_REGISTRY_STORAGE_SLOT =
    0x75becd3dc46851ccd9a9e74ae984f7607b7dfc21e393161cc0a3246962eb1100;
/// @dev 0x10928b13 is `type(IClaimTopicsRegistry).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x10928b13), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ICLAIMTOPICSREGISTRY_SLOT =
    0xfb0800521a41e28960f7a406ade656c595694178bf7b582791143ed7dc6ec311;

/// @custom:storage-location erc7201:lattice.storage.ERC3643ClaimTopicsRegistry
struct ERC3643ClaimTopicsRegistryData {
    EnumerableSet.UintSet _topics;
}

/// @title ERC3643ClaimTopicsRegistryLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Owner-managed required claim topics, capped at the standard's 15 entries.
library ERC3643ClaimTopicsRegistryLib {
    function state() internal pure returns (ERC3643ClaimTopicsRegistryData storage s) {
        assembly ("memory-safe") { s.slot := ERC3643_CLAIM_TOPICS_REGISTRY_STORAGE_SLOT }
    }

    function __ERC3643ClaimTopicsRegistry_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    function registerInterface() internal {
        assembly ("memory-safe") { sstore(ERC165_MAP_ICLAIMTOPICSREGISTRY_SLOT, true) }
    }
    using EnumerableSet for EnumerableSet.UintSet;

    function addClaimTopic(uint256 topic) internal {
        ERC3643ExecutionLib.enter();
        OwnableLib.checkOwner();
        ERC3643ClaimTopicsRegistryData storage s = state();
        if (s._topics.contains(topic)) revert IClaimTopicsRegistry.ERC3643ClaimTopicAlreadyRequired(topic);
        if (s._topics.length() == 15) revert IClaimTopicsRegistry.ERC3643ClaimTopicsLimit();
        s._topics.add(topic);
        emit IClaimTopicsRegistry.ClaimTopicAdded(topic);
        ERC3643ExecutionLib.exit();
    }

    function removeClaimTopic(uint256 topic) internal {
        ERC3643ExecutionLib.enter();
        OwnableLib.checkOwner();
        if (!state()._topics.remove(topic)) revert IClaimTopicsRegistry.ERC3643ClaimTopicNotRequired(topic);
        emit IClaimTopicsRegistry.ClaimTopicRemoved(topic);
        ERC3643ExecutionLib.exit();
    }

    function getClaimTopics() internal view returns (uint256[] memory) {
        return state()._topics.values();
    }
}
