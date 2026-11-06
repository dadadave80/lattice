// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DEFAULT_ENTRY_POINT} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";

/// @title AccountReleaseInventory
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Constructor-bound account release identities and the canonical facet-name blueprints.
/// @dev These are not stateless InitInventory entries or facets. A factory commits to its full cuts and init.
library AccountReleaseInventory {
    struct Entry {
        string initializer;
        string initializerArtifact;
        string factory;
        string factoryArtifact;
        string proxyKind;
        string proxyArtifact;
        address entryPoint;
        string entryPointVersion;
        bool modular;
    }

    function inventory() internal pure returns (Entry[] memory entries) {
        entries = new Entry[](6);
        address[3] memory entryPoints = [
            0x0000000071727De22E5E9d8BAf0edAc6f37da032, 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108, DEFAULT_ENTRY_POINT
        ];
        for (uint256 i; i < entries.length; ++i) {
            entries[i] = describe(i >= entryPoints.length, entryPoints[i % entryPoints.length]);
        }
    }

    /// @notice Custom EntryPoints remain usable, but are not part of the six-entry canonical release catalog.
    function describe(bool modular, address entryPoint) internal pure returns (Entry memory entry) {
        string memory suffix;
        string memory epVersion;
        if (entryPoint == 0x0000000071727De22E5E9d8BAf0edAc6f37da032) {
            suffix = "V07";
            epVersion = "0.7";
        } else if (entryPoint == 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108) {
            suffix = "V08";
            epVersion = "0.8";
        } else if (entryPoint == DEFAULT_ENTRY_POINT) {
            suffix = "V09";
            epVersion = "0.9";
        } else {
            suffix = "Custom";
            epVersion = "custom";
        }
        entry.initializer = string.concat(modular ? "AccountInit6900" : "AccountInit", suffix);
        entry.initializerArtifact = modular
            ? "src/accounts/erc6900/AccountInit6900.sol:AccountInit6900"
            : "src/accounts/erc7579/AccountInit.sol:AccountInit";
        entry.factory = string.concat(modular ? "AccountFactory6900" : "AccountFactory", suffix);
        entry.factoryArtifact = modular
            ? "src/accounts/erc6900/AccountFactory6900.sol:AccountFactory6900"
            : "src/accounts/erc7579/AccountFactory.sol:AccountFactory";
        entry.proxyKind = modular ? "ModularAccount6900" : "AccountDiamond";
        entry.proxyArtifact = modular
            ? "src/accounts/erc6900/ModularAccount6900.sol:ModularAccount6900"
            : "src/accounts/erc7579/AccountDiamond.sol:AccountDiamond";
        entry.entryPoint = entryPoint;
        entry.entryPointVersion = epVersion;
        entry.modular = modular;
    }

    function facetNames(bool modular) internal pure returns (string[] memory names) {
        names = new string[](modular ? 10 : 9);
        names[0] = "DiamondCutFacet";
        names[1] = "DiamondLoupeFacet";
        names[2] = "ERC165Facet";
        names[3] = "AccessControl";
        if (modular) {
            names[4] = "ERC6900ModuleManager";
            names[5] = "ERC6900Executor";
            names[6] = "ERC6900Validation";
            names[7] = "ERC6900Signature";
            names[8] = "ERC6900AccountView";
        } else {
            names[4] = "AccountSigner";
            names[5] = "ERC4337Validation";
            names[6] = "ERC1271Signature";
            names[7] = "ERC7821Executor";
        }
        names[names.length - 1] = "Receive";
    }
}
