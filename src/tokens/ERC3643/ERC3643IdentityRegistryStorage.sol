// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC3643Identity} from "@lattice/interfaces/external/erc3643/IERC3643Identity.sol";
import {IIdentityRegistryStorage} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistryStorage.sol";
import {
    ERC3643IdentityRegistryStorageLib
} from "@lattice/tokens/ERC3643/libraries/ERC3643IdentityRegistryStorageLib.sol";

/// @title ERC3643IdentityRegistryStorage
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Stateless standard IdentityRegistryStorage facet for the closed ERC-3643 suite.
/// @custom:lattice-source ERC-3643 CC0 standard
/// @custom:lattice-requires OwnableFacet convention registry-binding-administration;
/// @custom:lattice-family none
/// @custom:lattice-owns none;
/// @custom:lattice-touches lattice.storage.ERC3643IdentityRegistryStorage;
/// @custom:lattice-touches transient:lattice.storage.ERC3643Execution;
/// @custom:lattice-seam none;
/// @custom:lattice-init ERC3643Init
contract ERC3643IdentityRegistryStorage is IIdentityRegistryStorage {
    function bindIdentityRegistry(address registry) external {
        ERC3643IdentityRegistryStorageLib.bindIdentityRegistry(registry);
    }

    function unbindIdentityRegistry(address registry) external {
        ERC3643IdentityRegistryStorageLib.unbindIdentityRegistry(registry);
    }

    function linkedIdentityRegistries() external view returns (address[] memory) {
        return ERC3643IdentityRegistryStorageLib.linkedIdentityRegistries();
    }

    function addIdentityToStorage(address wallet, IERC3643Identity investorIdentity, uint16 country) external {
        ERC3643IdentityRegistryStorageLib.addIdentityToStorage(wallet, investorIdentity, country);
    }

    function removeIdentityFromStorage(address wallet) external {
        ERC3643IdentityRegistryStorageLib.removeIdentityFromStorage(wallet);
    }

    function modifyStoredInvestorCountry(address wallet, uint16 country) external {
        ERC3643IdentityRegistryStorageLib.modifyStoredInvestorCountry(wallet, country);
    }

    function modifyStoredIdentity(address wallet, IERC3643Identity investorIdentity) external {
        ERC3643IdentityRegistryStorageLib.modifyStoredIdentity(wallet, investorIdentity);
    }

    function storedIdentity(address wallet) external view returns (IERC3643Identity) {
        return ERC3643IdentityRegistryStorageLib.storedIdentity(wallet);
    }

    function storedInvestorCountry(address wallet) external view returns (uint16) {
        return ERC3643IdentityRegistryStorageLib.storedInvestorCountry(wallet);
    }

    /// @notice ERC-8153 packed selectors; excludes exportSelectors itself.
    function exportSelectors() external pure returns (bytes memory) {
        return hex"a53410dd690a49f9bf9eb959e805cf869f3418d5cf191bcd7988d3a5727e13bc97a012f7";
    }
}
