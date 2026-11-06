// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {RecipePlanLib} from "@lattice-script/lib/RecipePlanLib.sol";
import {
    RecipeAuthority,
    RecipeDeploymentContext,
    RecipeFacet,
    RecipeInitOutputKind,
    RecipeParameter,
    RecipeProxyKind,
    RecipeSeam,
    RecipeSpec,
    RecipeVariant
} from "@lattice-script/lib/RecipeSpec.sol";
import {RecipeSpecLib} from "@lattice-script/lib/RecipeSpecLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {TellorAdapter} from "@lattice/oracles/tellor/TellorAdapter.sol";
import {TellorAdapterInit} from "@lattice/oracles/tellor/TellorAdapterInit.sol";

/// @title DeployTellorAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Tellor price-feed adapter diamond: `ERC165Facet` + `AccessControl` +
///         `TellorAdapter` + {TellorAdapterInit}. The ONE source of truth for what a Tellor adapter diamond is,
///         shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because the feed-registry setters and `setTellor` are
///         `DEFAULT_ADMIN_ROLE`-gated. Unlike the registry-only adapters, the Tellor oracle is wired at init.
contract DeployTellorAdapter is BaseDeploy {
    /// @notice Builds the Tellor adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the feed registry and `setTellor`).
    /// @param tellor The Tellor oracle contract the adapter reads reports from (reverts if zero).
    /// @return cuts The facet cuts (ERC165 + AccessControl + TellorAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {TellorAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address tellor)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("TellorAdapterInit"), abi.encodeCall(TellorAdapterInit.init, (admin, tellor))
        );
    }

    function _cutPlan(uint256) internal pure returns (RecipeFacet[] memory facets) {
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("TellorAdapter");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cuts, typed initializer bindings and deployment context as pure script data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployTellorAdapter", "script/base/oracles/DeployTellorAdapter.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployTellorAdapter:buildCuts(address,address)";
        variant.buildSignature = "buildCuts(address,address)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Single;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](2);
        variant.inputs[0] = RecipeParameter(
            "admin",
            "address",
            "account",
            "0x00000000000000000000000000000000000000ad",
            "caller: choose a usable role administrator and upgrade authority; initialization permits the zero address"
        );
        variant.inputs[1] = RecipeParameter(
            "tellor",
            "address",
            "Tellor-contract-address",
            "mock-or-target-configured-Tellor",
            "enforced at initialization: nonzero; caller authenticates the target-chain Tellor implementation"
        );
        string[] memory bindings = new string[](2);
        bindings[0] = "admin";
        bindings[1] = "tellor";
        variant.initPlan = RecipeSpecLib.introspected(
            RecipeSpecLib.leaf("TellorAdapterInit", "init(address,address)", variant.inputs, bindings), true
        );
        variant.authorities = new RecipeAuthority[](1);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "module configuration, role administration and diamondCut"
        );
        variant.conditions = new string[](2);
        variant.conditions[0] = "caller: register query IDs, dispute buffers and staleness limits after initialization";
        variant.conditions[1] =
        "caller: authenticate external service configuration; this recipe does not verify live providers";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployTellorAdapter", "run(address,address)", variant, "buildCuts(admin,tellor)"
        );
    }

    /// @notice Deploys a Tellor adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The feed-registry admin.
    /// @param tellor The Tellor oracle contract reference.
    /// @return adapter The deployed Tellor adapter diamond address.
    function run(address admin, address tellor) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, tellor);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
