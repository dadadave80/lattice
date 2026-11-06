// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccountReleaseInventory} from "@lattice-script/lib/AccountReleaseInventory.sol";
import {FacetInventory} from "@lattice-script/lib/FacetInventory.sol";
import {InitInventory} from "@lattice-script/lib/InitInventory.sol";
import {RecipeInventory} from "@lattice-script/lib/RecipeInventory.sol";
import {IRecipeSpec, RecipeSpec} from "@lattice-script/lib/RecipeSpec.sol";
import {LatticeVersion} from "@lattice/LatticeVersion.sol";
import {Script} from "forge-std/Script.sol";

/// @title GenerateRecipes
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Collect pure recipe data locally, using the compiler ABI's native named serialization schema.
/// @dev No broadcast or module initialization. Native cheatcodes instantiate script artifacts locally;
///      the full catalogue must fit the default script limits without any shared configuration override.
contract GenerateRecipes is Script {
    /// @notice Write the canonical inventory and schema metadata without constructing all recipe scripts.
    function inventory(string memory typeDescription, string memory destination) external {
        (string[] memory names, string[] memory artifacts) = RecipeInventory.inventory();
        string memory key = "recipes:inventory";
        vm.serializeJson(
            key,
            string.concat(
                '{"accountProfiles":',
                _accountProfiles(),
                ',"excludedContexts":',
                '[{"name":"CCTPHookDemo","source":"script/base/crosschain/CCTPHookDemo.s.sol","canonicalParent":"DeployCCTPBridgeAdapter","disposition":"chain-specific multichain demo; inherits canonical builder but has custom setup/actions"},{"name":"CCTPUSDCDemo","source":"script/base/crosschain/CCTPUSDCDemo.s.sol","canonicalParent":"DeployCCTPBridgeAdapter","disposition":"chain-specific multichain demo; inherits canonical builder but has custom setup/actions"},{"name":"CCTPHookReceiptDemo","source":"script/base/crosschain/CCTPHookReceiptDemo.s.sol","canonicalParent":"","disposition":"standalone receipt example; deploys no diamond recipe"},{"name":"GrantExample","source":"script/base/defi/GrantExample.s.sol","canonicalParent":"DeployGovernedVault","disposition":"testnet example adds asset/probe and inherits canonical vault builder"}]',
                "}"
            )
        );
        vm.serializeString(key, "names", names);
        vm.serializeString(key, "artifacts", artifacts);
        (string[] memory facetNames, string[] memory facetArtifacts) = FacetInventory.inventory();
        vm.serializeString(key, "facetNames", facetNames);
        vm.serializeString(key, "facetArtifacts", facetArtifacts);
        (string[] memory initNames, string[] memory initArtifacts) = InitInventory.inventory();
        vm.serializeString(key, "initializerNames", initNames);
        vm.serializeString(key, "initializerArtifacts", initArtifacts);
        string[] memory helpers = new string[](3);
        helpers[0] = "script/base/BaseDeploy.s.sol";
        helpers[1] = "script/base/accounts/AccountDeployBase.s.sol";
        helpers[2] = "script/base/tokens/TokenDeployBase.s.sol";
        vm.serializeString(key, "abstractHelpers", helpers);
        vm.serializeUint(key, "schemaVersion", 1);
        vm.serializeString(key, "latticeVersion", LatticeVersion.VERSION);
        vm.writeJson(vm.serializeString(key, "typeDescription", typeDescription), destination);
    }

    /// @notice Collect one bounded record; the native wrapper joins all records without aggregate deployment gas.
    function generate(
        string memory name,
        string memory artifact,
        string memory typeDescription,
        string memory destination
    ) external {
        vm.writeJson(_reader().record(name, artifact, typeDescription), destination);
    }

    function _accountProfiles() private returns (string memory json) {
        AccountReleaseInventory.Entry[] memory entries = AccountReleaseInventory.inventory();
        string memory description =
            "AccountProfile(string initializer,string initializerArtifact,string factory,string factoryArtifact,string proxyKind,string proxyArtifact,address entryPoint,string entryPointVersion,bool modular)";
        json = "[";
        for (uint256 i; i < entries.length; ++i) {
            bytes memory encoded = abi.encode(entries[i]);
            string memory record = vm.serializeJsonType(description, encoded);
            require(
                keccak256(vm.parseJsonType(record, description)) == keccak256(encoded),
                "recipes: account profile serialization changed ABI bytes"
            );
            json = string.concat(json, i == 0 ? "" : ",", record);
        }
        json = string.concat(json, "]");
    }

    function _reader() private returns (RecipeSpecReader) {
        return RecipeSpecReader(vm.deployCode("script/recipes/GenerateRecipes.s.sol:RecipeSpecReader"));
    }
}

/// @title RecipeSpecReader
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Independent local-only frame for recipe return decoding and lossless native serialization.
contract RecipeSpecReader is Script {
    error RecipeNameMismatch(string artifact, string expected, string actual);
    error RecipeSerializationMismatch(string artifact);

    /// @dev One recipe's code, return decoding and native serialization have their own bounded memory frame.
    function record(string memory name, string memory artifact, string memory typeDescription)
        external
        returns (string memory json)
    {
        address at = vm.deployCode(artifact);
        RecipeSpec memory spec = IRecipeSpec(at).recipeSpec();
        if (keccak256(bytes(spec.name)) != keccak256(bytes(name))) {
            revert RecipeNameMismatch(artifact, name, spec.name);
        }
        bytes memory encoded = abi.encode(spec);
        json = vm.serializeJsonType(typeDescription, encoded);
        if (keccak256(vm.parseJsonType(json, typeDescription)) != keccak256(encoded)) {
            revert RecipeSerializationMismatch(artifact);
        }
    }
}
