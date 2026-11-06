// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {IERC3643ClaimIssuer} from "@lattice/interfaces/external/erc3643/IERC3643ClaimIssuer.sol";
import {ITrustedIssuersRegistry} from "@lattice/interfaces/tokens/erc3643/ITrustedIssuersRegistry.sol";
import {ERC3643ExecutionLib} from "@lattice/tokens/ERC3643/libraries/ERC3643ExecutionLib.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC3643TrustedIssuersRegistry")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC3643_TRUSTED_ISSUERS_REGISTRY_STORAGE_SLOT =
    0x5378a9ff2d49f0b9d9a96809a7b737e6b13fb211786455938311f4d4d34ee500;
/// @dev 0xb0f773b8 is `type(ITrustedIssuersRegistry).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xb0f773b8), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ITRUSTEDISSUERSREGISTRY_SLOT =
    0x1581f45088ce8cd867e9eb74d20ba9c1676b618fa0eca24f95a10e1e759db18a;

/// @custom:storage-location erc7201:lattice.storage.ERC3643TrustedIssuersRegistry
struct ERC3643TrustedIssuersRegistryData {
    EnumerableSet.AddressSet _issuers;
    mapping(address issuer => EnumerableSet.UintSet) _topics;
    mapping(uint256 topic => EnumerableSet.AddressSet) _topicIssuers;
}

/// @title ERC3643TrustedIssuersRegistryLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Owner-managed trusted issuers and topic memberships with synchronized reverse indexes.
library ERC3643TrustedIssuersRegistryLib {
    function state() internal pure returns (ERC3643TrustedIssuersRegistryData storage s) {
        assembly ("memory-safe") { s.slot := ERC3643_TRUSTED_ISSUERS_REGISTRY_STORAGE_SLOT }
    }

    function __ERC3643TrustedIssuersRegistry_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    function registerInterface() internal {
        assembly ("memory-safe") { sstore(ERC165_MAP_ITRUSTEDISSUERSREGISTRY_SLOT, true) }
    }
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    function addTrustedIssuer(IERC3643ClaimIssuer issuer, uint256[] memory topics) internal {
        ERC3643ExecutionLib.enter();
        OwnableLib.checkOwner();
        address endpoint = address(issuer);
        if (endpoint == address(0) || endpoint.code.length == 0) {
            revert ITrustedIssuersRegistry.ERC3643InvalidIssuer(endpoint);
        }
        if (isTrustedIssuer(endpoint)) revert ITrustedIssuersRegistry.ERC3643IssuerAlreadyTrusted(endpoint);
        if (state()._issuers.length() == 50) revert ITrustedIssuersRegistry.ERC3643TrustedIssuersLimit();
        _checkTopicsLength(topics.length);
        state()._issuers.add(endpoint);
        _replaceTopics(endpoint, topics);
        emit ITrustedIssuersRegistry.TrustedIssuerAdded(issuer, state()._topics[endpoint].values());
        ERC3643ExecutionLib.exit();
    }

    function removeTrustedIssuer(IERC3643ClaimIssuer issuer) internal {
        ERC3643ExecutionLib.enter();
        OwnableLib.checkOwner();
        address endpoint = address(issuer);
        if (!state()._issuers.remove(endpoint)) revert ITrustedIssuersRegistry.ERC3643IssuerNotTrusted(endpoint);
        _replaceTopics(endpoint, new uint256[](0));
        emit ITrustedIssuersRegistry.TrustedIssuerRemoved(issuer);
        ERC3643ExecutionLib.exit();
    }

    function updateIssuerClaimTopics(IERC3643ClaimIssuer issuer, uint256[] memory topics) internal {
        ERC3643ExecutionLib.enter();
        OwnableLib.checkOwner();
        address endpoint = address(issuer);
        if (!isTrustedIssuer(endpoint)) revert ITrustedIssuersRegistry.ERC3643IssuerNotTrusted(endpoint);
        _checkTopicsLength(topics.length);
        _replaceTopics(endpoint, topics);
        emit ITrustedIssuersRegistry.ClaimTopicsUpdated(issuer, state()._topics[endpoint].values());
        ERC3643ExecutionLib.exit();
    }

    function _checkTopicsLength(uint256 length) private pure {
        if (length == 0 || length > 15) revert ITrustedIssuersRegistry.ERC3643IssuerTopicsLength(length);
    }

    function _replaceTopics(address issuer, uint256[] memory topics) private {
        ERC3643TrustedIssuersRegistryData storage s = state();
        while (s._topics[issuer].length() != 0) {
            uint256 old = s._topics[issuer].at(s._topics[issuer].length() - 1);
            s._topics[issuer].remove(old);
            s._topicIssuers[old].remove(issuer);
        }
        for (uint256 i; i < topics.length; ++i) {
            if (s._topics[issuer].add(topics[i])) s._topicIssuers[topics[i]].add(issuer);
        }
    }

    function getTrustedIssuers() internal view returns (IERC3643ClaimIssuer[] memory) {
        return _typed(state()._issuers.values());
    }

    function getTrustedIssuersForClaimTopic(uint256 topic) internal view returns (IERC3643ClaimIssuer[] memory) {
        return _typed(state()._topicIssuers[topic].values());
    }

    function _typed(address[] memory addresses) private pure returns (IERC3643ClaimIssuer[] memory result) {
        result = new IERC3643ClaimIssuer[](addresses.length);
        for (uint256 i; i < addresses.length; ++i) {
            result[i] = IERC3643ClaimIssuer(addresses[i]);
        }
    }

    function isTrustedIssuer(address issuer) internal view returns (bool) {
        return state()._issuers.contains(issuer);
    }

    function getTrustedIssuerClaimTopics(IERC3643ClaimIssuer issuer) internal view returns (uint256[] memory) {
        return state()._topics[address(issuer)].values();
    }

    function hasClaimTopic(address issuer, uint256 topic) internal view returns (bool) {
        return isTrustedIssuer(issuer) && state()._topics[issuer].contains(topic);
    }
}
