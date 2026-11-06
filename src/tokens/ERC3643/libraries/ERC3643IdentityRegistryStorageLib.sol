// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {IERC3643Identity} from "@lattice/interfaces/external/erc3643/IERC3643Identity.sol";
import {IIdentityRegistryStorage} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistryStorage.sol";
import {ERC3643ExecutionLib} from "@lattice/tokens/ERC3643/libraries/ERC3643ExecutionLib.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC3643IdentityRegistryStorage")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC3643_IDENTITY_REGISTRY_STORAGE_SLOT =
    0xe887ffba65a77a04a49755f77f35ff689ea1d47eb3c26a4ae93fc39e1696fb00;
/// @dev 0x57defe0d is `type(IIdentityRegistryStorage).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x57defe0d), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IIDENTITYREGISTRYSTORAGE_SLOT =
    0x76c31b23f779d640712776c8fc2183ef2248d79a58156d6e4ba36486cb057f27;

struct ERC3643IdentityRecord {
    IERC3643Identity identity;
    uint16 country;
}

/// @custom:storage-location erc7201:lattice.storage.ERC3643IdentityRegistryStorage
struct ERC3643IdentityRegistryStorageData {
    mapping(address wallet => ERC3643IdentityRecord) _identities;
    EnumerableSet.AddressSet _registries;
}

/// @title ERC3643IdentityRegistryStorageLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Identity records shared only with owner-bound registries, including counterfactual addresses.
library ERC3643IdentityRegistryStorageLib {
    using EnumerableSet for EnumerableSet.AddressSet;

    function state() internal pure returns (ERC3643IdentityRegistryStorageData storage s) {
        assembly ("memory-safe") { s.slot := ERC3643_IDENTITY_REGISTRY_STORAGE_SLOT }
    }

    function __ERC3643IdentityRegistryStorage_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    function registerInterface() internal {
        assembly ("memory-safe") { sstore(ERC165_MAP_IIDENTITYREGISTRYSTORAGE_SLOT, true) }
    }

    function isBound(address registry) internal view returns (bool) {
        return state()._registries.contains(registry);
    }

    function checkBound(address registry) internal view {
        if (!isBound(registry)) revert IIdentityRegistryStorage.ERC3643UnauthorizedRegistry(registry);
    }

    function bindIdentityRegistry(address registry) internal {
        ERC3643ExecutionLib.enter();
        OwnableLib.checkOwner();
        _bindIdentityRegistry(registry);
        ERC3643ExecutionLib.exit();
    }

    function _bindIdentityRegistry(address registry) internal {
        if (registry == address(0)) revert IIdentityRegistryStorage.ERC3643InvalidRegistry(registry);
        ERC3643IdentityRegistryStorageData storage s = state();
        if (s._registries.contains(registry)) revert IIdentityRegistryStorage.ERC3643RegistryAlreadyBound(registry);
        if (s._registries.length() == 300) revert IIdentityRegistryStorage.ERC3643RegistryLimit();
        s._registries.add(registry);
        emit IIdentityRegistryStorage.IdentityRegistryBound(registry);
    }

    function unbindIdentityRegistry(address registry) internal {
        ERC3643ExecutionLib.enter();
        OwnableLib.checkOwner();
        if (!state()._registries.remove(registry)) revert IIdentityRegistryStorage.ERC3643RegistryNotBound(registry);
        emit IIdentityRegistryStorage.IdentityRegistryUnbound(registry);
        ERC3643ExecutionLib.exit();
    }

    function linkedIdentityRegistries() internal view returns (address[] memory) {
        return state()._registries.values();
    }

    function addIdentityToStorage(address wallet, IERC3643Identity investorIdentity, uint16 country) internal {
        ERC3643ExecutionLib.enter();
        checkBound(msg.sender);
        _addIdentityToStorage(wallet, investorIdentity, country);
        ERC3643ExecutionLib.exit();
    }

    function _addIdentityToStorage(address wallet, IERC3643Identity investorIdentity, uint16 country) internal {
        _validateWalletAndIdentity(wallet, investorIdentity);
        if (address(storedIdentity(wallet)) != address(0)) {
            revert IIdentityRegistryStorage.ERC3643IdentityAlreadyStored(wallet);
        }
        state()._identities[wallet] = ERC3643IdentityRecord(investorIdentity, country);
        emit IIdentityRegistryStorage.IdentityStored(wallet, investorIdentity);
    }

    function removeIdentityFromStorage(address wallet) internal {
        ERC3643ExecutionLib.enter();
        checkBound(msg.sender);
        _removeIdentityFromStorage(wallet);
        ERC3643ExecutionLib.exit();
    }

    function _removeIdentityFromStorage(address wallet) internal {
        IERC3643Identity previous = _requireIdentity(wallet);
        delete state()._identities[wallet];
        emit IIdentityRegistryStorage.IdentityUnstored(wallet, previous);
    }

    function modifyStoredInvestorCountry(address wallet, uint16 country) internal {
        ERC3643ExecutionLib.enter();
        checkBound(msg.sender);
        _modifyStoredInvestorCountry(wallet, country);
        ERC3643ExecutionLib.exit();
    }

    function _modifyStoredInvestorCountry(address wallet, uint16 country) internal {
        _requireIdentity(wallet);
        state()._identities[wallet].country = country;
        emit IIdentityRegistryStorage.CountryModified(wallet, country);
    }

    function modifyStoredIdentity(address wallet, IERC3643Identity investorIdentity) internal {
        ERC3643ExecutionLib.enter();
        checkBound(msg.sender);
        _modifyStoredIdentity(wallet, investorIdentity);
        ERC3643ExecutionLib.exit();
    }

    function _modifyStoredIdentity(address wallet, IERC3643Identity investorIdentity) internal {
        IERC3643Identity previous = _requireIdentity(wallet);
        _validateWalletAndIdentity(wallet, investorIdentity);
        (bool ok, bytes memory result) = address(investorIdentity)
            .staticcall(abi.encodeCall(IERC3643Identity.keyHasPurpose, (keccak256(abi.encode(wallet)), uint256(1))));
        uint256 word;
        if (ok && result.length == 32) {
            assembly ("memory-safe") { word := mload(add(result, 32)) }
        }
        if (word != 1) revert IIdentityRegistryStorage.ERC3643IdentityKeyMissing(address(investorIdentity), wallet);
        state()._identities[wallet].identity = investorIdentity;
        emit IIdentityRegistryStorage.IdentityModified(previous, investorIdentity);
    }

    function _validateWalletAndIdentity(address wallet, IERC3643Identity investorIdentity) private view {
        if (wallet == address(0)) revert IIdentityRegistryStorage.ERC3643InvalidInvestor(wallet);
        address endpoint = address(investorIdentity);
        if (endpoint == address(0) || endpoint.code.length == 0) {
            revert IIdentityRegistryStorage.ERC3643InvalidIdentity(endpoint);
        }
    }

    function _requireIdentity(address wallet) private view returns (IERC3643Identity value) {
        value = storedIdentity(wallet);
        if (address(value) == address(0)) revert IIdentityRegistryStorage.ERC3643IdentityNotStored(wallet);
    }

    function storedIdentity(address wallet) internal view returns (IERC3643Identity) {
        return state()._identities[wallet].identity;
    }

    function storedInvestorCountry(address wallet) internal view returns (uint16) {
        return state()._identities[wallet].country;
    }
}
