// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {IERC3643ClaimIssuer} from "@lattice/interfaces/external/erc3643/IERC3643ClaimIssuer.sol";
import {IERC3643Identity} from "@lattice/interfaces/external/erc3643/IERC3643Identity.sol";
import {IClaimTopicsRegistry} from "@lattice/interfaces/tokens/erc3643/IClaimTopicsRegistry.sol";
import {IIdentityRegistry} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistry.sol";
import {IIdentityRegistryStorage} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistryStorage.sol";
import {ITrustedIssuersRegistry} from "@lattice/interfaces/tokens/erc3643/ITrustedIssuersRegistry.sol";
import {ERC3643AgentRoleLib} from "@lattice/tokens/ERC3643/libraries/ERC3643AgentRoleLib.sol";
import {ERC3643ClaimTopicsRegistryLib} from "@lattice/tokens/ERC3643/libraries/ERC3643ClaimTopicsRegistryLib.sol";
import {ERC3643ExecutionLib} from "@lattice/tokens/ERC3643/libraries/ERC3643ExecutionLib.sol";
import {
    ERC3643IdentityRegistryStorageLib
} from "@lattice/tokens/ERC3643/libraries/ERC3643IdentityRegistryStorageLib.sol";
import {ERC3643TrustedIssuersRegistryLib} from "@lattice/tokens/ERC3643/libraries/ERC3643TrustedIssuersRegistryLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC3643IdentityRegistry")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC3643_IDENTITY_REGISTRY_STORAGE_ROOT =
    0x0ea0b7136671cc454d4dbd6846eb4555e21642d317fda5e88aa0aa0398c0ed00;
/// @dev 0x8ff89f73 is `type(IIdentityRegistry).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x8ff89f73), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IIDENTITYREGISTRY_SLOT = 0x1432554cd2aff9b2bdec5e9b776ed6f1cb4c1249efb6e06e0d30d4d2282073f8;

/// @custom:storage-location erc7201:lattice.storage.ERC3643IdentityRegistry
struct ERC3643IdentityRegistryData {
    address _identityStorage;
    address _issuersRegistry;
    address _topicsRegistry;
}

/// @title ERC3643IdentityRegistryLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Agent-managed investor identities and fresh checks of every required topic and trusted issuer.
/// @dev External claims and validation stay external; no reference signature/revocation implementation is copied.
library ERC3643IdentityRegistryLib {
    function state() internal pure returns (ERC3643IdentityRegistryData storage s) {
        assembly ("memory-safe") { s.slot := ERC3643_IDENTITY_REGISTRY_STORAGE_ROOT }
    }

    function __ERC3643IdentityRegistry_init(address storage_, address issuers_, address topics_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        _setIdentityRegistryStorage(storage_);
        _setTrustedIssuersRegistry(issuers_);
        _setClaimTopicsRegistry(topics_);
        registerInterface();
    }

    function registerInterface() internal {
        assembly ("memory-safe") { sstore(ERC165_MAP_IIDENTITYREGISTRY_SLOT, true) }
    }

    function identityStorage() internal view returns (IIdentityRegistryStorage) {
        return IIdentityRegistryStorage(state()._identityStorage);
    }

    function issuersRegistry() internal view returns (ITrustedIssuersRegistry) {
        return ITrustedIssuersRegistry(state()._issuersRegistry);
    }

    function topicsRegistry() internal view returns (IClaimTopicsRegistry) {
        return IClaimTopicsRegistry(state()._topicsRegistry);
    }

    function setIdentityRegistryStorage(address endpoint) internal {
        ERC3643ExecutionLib.enter();
        OwnableLib.checkOwner();
        _setIdentityRegistryStorage(endpoint);
        ERC3643ExecutionLib.exit();
    }

    function _setIdentityRegistryStorage(address endpoint) private {
        _requireCode(endpoint);
        _checkStorageBinding(endpoint);
        state()._identityStorage = endpoint;
        emit IIdentityRegistry.IdentityStorageSet(endpoint);
    }

    function setTrustedIssuersRegistry(address endpoint) internal {
        ERC3643ExecutionLib.enter();
        OwnableLib.checkOwner();
        _setTrustedIssuersRegistry(endpoint);
        ERC3643ExecutionLib.exit();
    }

    function _setTrustedIssuersRegistry(address endpoint) private {
        _requireCode(endpoint);
        state()._issuersRegistry = endpoint;
        emit IIdentityRegistry.TrustedIssuersRegistrySet(endpoint);
    }

    function setClaimTopicsRegistry(address endpoint) internal {
        ERC3643ExecutionLib.enter();
        OwnableLib.checkOwner();
        _setClaimTopicsRegistry(endpoint);
        ERC3643ExecutionLib.exit();
    }

    function _setClaimTopicsRegistry(address endpoint) private {
        _requireCode(endpoint);
        state()._topicsRegistry = endpoint;
        emit IIdentityRegistry.ClaimTopicsRegistrySet(endpoint);
    }

    function _requireCode(address endpoint) private view {
        if (endpoint == address(0) || endpoint.code.length == 0) {
            revert IIdentityRegistry.ERC3643InvalidRegistryDependency(endpoint);
        }
    }

    function _checkStorageBinding(address endpoint) private view {
        if (endpoint == address(this)) {
            if (ERC3643IdentityRegistryStorageLib.isBound(address(this))) return;
        } else {
            address[] memory registries = IIdentityRegistryStorage(endpoint).linkedIdentityRegistries();
            for (uint256 i; i < registries.length; ++i) {
                if (registries[i] == address(this)) return;
            }
        }
        revert IIdentityRegistry.ERC3643UnboundIdentityStorage(endpoint, address(this));
    }

    function _storageEndpoint() private view returns (address endpoint) {
        endpoint = state()._identityStorage;
        _requireCode(endpoint);
    }

    function registerIdentity(address wallet, IERC3643Identity investorIdentity, uint16 country) internal {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        _registerIdentity(wallet, investorIdentity, country);
        ERC3643ExecutionLib.exit();
    }

    function _registerIdentity(address wallet, IERC3643Identity investorIdentity, uint16 country) internal {
        address endpoint = _storageEndpoint();
        if (endpoint == address(this)) {
            ERC3643IdentityRegistryStorageLib.checkBound(address(this));
            ERC3643IdentityRegistryStorageLib._addIdentityToStorage(wallet, investorIdentity, country);
        } else {
            IIdentityRegistryStorage(endpoint).addIdentityToStorage(wallet, investorIdentity, country);
        }
        emit IIdentityRegistry.IdentityRegistered(wallet, investorIdentity);
    }

    function deleteIdentity(address wallet) internal {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        _deleteIdentity(wallet);
        ERC3643ExecutionLib.exit();
    }

    function _deleteIdentity(address wallet) internal {
        IERC3643Identity previous = identity(wallet);
        address endpoint = _storageEndpoint();
        if (endpoint == address(this)) {
            ERC3643IdentityRegistryStorageLib.checkBound(address(this));
            ERC3643IdentityRegistryStorageLib._removeIdentityFromStorage(wallet);
        } else {
            IIdentityRegistryStorage(endpoint).removeIdentityFromStorage(wallet);
        }
        emit IIdentityRegistry.IdentityRemoved(wallet, previous);
    }

    function updateCountry(address wallet, uint16 country) internal {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        address endpoint = _storageEndpoint();
        if (endpoint == address(this)) {
            ERC3643IdentityRegistryStorageLib.checkBound(address(this));
            ERC3643IdentityRegistryStorageLib._modifyStoredInvestorCountry(wallet, country);
        } else {
            IIdentityRegistryStorage(endpoint).modifyStoredInvestorCountry(wallet, country);
        }
        emit IIdentityRegistry.CountryUpdated(wallet, country);
        ERC3643ExecutionLib.exit();
    }

    function updateIdentity(address wallet, IERC3643Identity investorIdentity) internal {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        IERC3643Identity previous = identity(wallet);
        address endpoint = _storageEndpoint();
        if (endpoint == address(this)) {
            ERC3643IdentityRegistryStorageLib.checkBound(address(this));
            ERC3643IdentityRegistryStorageLib._modifyStoredIdentity(wallet, investorIdentity);
        } else {
            IIdentityRegistryStorage(endpoint).modifyStoredIdentity(wallet, investorIdentity);
        }
        emit IIdentityRegistry.IdentityUpdated(previous, investorIdentity);
        ERC3643ExecutionLib.exit();
    }

    function batchRegisterIdentity(
        address[] memory wallets,
        IERC3643Identity[] memory identities,
        uint16[] memory countries
    ) internal {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        if (wallets.length != identities.length || wallets.length != countries.length) {
            revert IIdentityRegistry.ERC3643RegistryArrayLengths();
        }
        for (uint256 i; i < wallets.length; ++i) {
            _registerIdentity(wallets[i], identities[i], countries[i]);
        }
        ERC3643ExecutionLib.exit();
    }

    function identity(address wallet) internal view returns (IERC3643Identity) {
        address endpoint = _storageEndpoint();
        return endpoint == address(this)
            ? ERC3643IdentityRegistryStorageLib.storedIdentity(wallet)
            : IIdentityRegistryStorage(endpoint).storedIdentity(wallet);
    }

    function investorCountry(address wallet) internal view returns (uint16) {
        address endpoint = _storageEndpoint();
        return endpoint == address(this)
            ? ERC3643IdentityRegistryStorageLib.storedInvestorCountry(wallet)
            : IIdentityRegistryStorage(endpoint).storedInvestorCountry(wallet);
    }

    function contains(address wallet) internal view returns (bool) {
        return address(identity(wallet)) != address(0);
    }

    function isVerified(address wallet) internal view returns (bool) {
        if (wallet == address(0) || state()._identityStorage == address(0)) return false;
        IERC3643Identity investorIdentity = identity(wallet);
        if (address(investorIdentity).code.length == 0) return false;
        uint256[] memory topics = _requiredTopics();
        for (uint256 i; i < topics.length; ++i) {
            IERC3643ClaimIssuer[] memory issuers = _issuersForTopic(topics[i]);
            bool valid;
            for (uint256 j; j < issuers.length; ++j) {
                address issuer = address(issuers[j]);
                if (_authorizedIssuer(issuer, topics[i]) && _validClaim(investorIdentity, issuer, topics[i])) {
                    valid = true;
                    break;
                }
            }
            if (!valid) return false;
        }
        return true;
    }

    function _requiredTopics() private view returns (uint256[] memory) {
        address endpoint = state()._topicsRegistry;
        _requireCode(endpoint);
        return endpoint == address(this)
            ? ERC3643ClaimTopicsRegistryLib.getClaimTopics()
            : IClaimTopicsRegistry(endpoint).getClaimTopics();
    }

    function _issuersForTopic(uint256 topic) private view returns (IERC3643ClaimIssuer[] memory) {
        address endpoint = state()._issuersRegistry;
        _requireCode(endpoint);
        return endpoint == address(this)
            ? ERC3643TrustedIssuersRegistryLib.getTrustedIssuersForClaimTopic(topic)
            : ITrustedIssuersRegistry(endpoint).getTrustedIssuersForClaimTopic(topic);
    }

    function _authorizedIssuer(address issuer, uint256 topic) private view returns (bool) {
        if (issuer.code.length == 0) return false;
        address endpoint = state()._issuersRegistry;
        if (endpoint == address(this)) return ERC3643TrustedIssuersRegistryLib.hasClaimTopic(issuer, topic);
        return _staticBool(endpoint, abi.encodeCall(ITrustedIssuersRegistry.isTrustedIssuer, (issuer)))
            && _staticBool(endpoint, abi.encodeCall(ITrustedIssuersRegistry.hasClaimTopic, (issuer, topic)));
    }

    function _validClaim(IERC3643Identity investorIdentity, address issuer, uint256 topic) private view returns (bool) {
        (bool ok, bytes memory result) = address(investorIdentity)
            .staticcall(abi.encodeCall(IERC3643Identity.getClaim, (keccak256(abi.encode(issuer, topic)))));
        if (!ok || result.length < 192 || _word(result, 0) != topic || _word(result, 64) != uint256(uint160(issuer))) {
            return false;
        }
        (bool signatureOk, bytes memory signature) = _dynamicBytes(result, _word(result, 96));
        if (!signatureOk) return false;
        (bool dataOk, bytes memory data) = _dynamicBytes(result, _word(result, 128));
        if (!dataOk) return false;
        (bool uriOk,) = _dynamicRange(result, _word(result, 160));
        if (!uriOk) return false;
        return _staticBool(
            issuer, abi.encodeCall(IERC3643ClaimIssuer.isClaimValid, (investorIdentity, topic, signature, data))
        );
    }

    function _word(bytes memory data, uint256 offset) private pure returns (uint256 value) {
        assembly ("memory-safe") { value := mload(add(add(data, 32), offset)) }
    }

    function _dynamicRange(bytes memory data, uint256 offset) private pure returns (bool, uint256) {
        if (offset < 192 || offset % 32 != 0 || offset > data.length - 32) return (false, 0);
        uint256 length = _word(data, offset);
        if (length > data.length - offset - 32) return (false, 0);
        return (true, length);
    }

    function _dynamicBytes(bytes memory data, uint256 offset) private pure returns (bool, bytes memory result) {
        (bool valid, uint256 length) = _dynamicRange(data, offset);
        if (!valid) return (false, result);
        result = new bytes(length);
        for (uint256 i; i < length; ++i) {
            result[i] = data[offset + 32 + i];
        }
        return (true, result);
    }

    function _staticBool(address endpoint, bytes memory input) private view returns (bool) {
        (bool ok, bytes memory result) = endpoint.staticcall(input);
        if (!ok || result.length != 32) return false;
        return _word(result, 0) == 1;
    }
}
