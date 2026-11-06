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
import {PythEntropyAdapter} from "@lattice/oracles/pyth/PythEntropyAdapter.sol";
import {PythEntropyAdapterInit} from "@lattice/oracles/pyth/PythEntropyAdapterInit.sol";

/// @title DeployPythEntropyAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Pyth Entropy randomness diamond: `ERC165Facet` + `AccessControl` +
///         `PythEntropyAdapter` + {PythEntropyAdapterInit}. The ONE source of truth for what an entropy diamond
///         is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because every config/request setter is admin-gated.
contract DeployPythEntropyAdapter is BaseDeploy {
    /// @notice Builds the Pyth Entropy diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the entropy config + request setters).
    /// @return cuts The facet cuts (ERC165 + AccessControl + PythEntropyAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {PythEntropyAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("PythEntropyAdapterInit"), abi.encodeCall(PythEntropyAdapterInit.init, (admin))
        );
    }

    function _cutPlan(uint256) internal pure returns (RecipeFacet[] memory facets) {
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("PythEntropyAdapter");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cuts, typed initializer bindings and deployment context as pure script data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployPythEntropyAdapter", "script/base/oracles/DeployPythEntropyAdapter.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployPythEntropyAdapter:buildCuts(address)";
        variant.buildSignature = "buildCuts(address)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Single;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](1);
        variant.inputs[0] = RecipeParameter(
            "admin",
            "address",
            "account",
            "0x00000000000000000000000000000000000000ad",
            "caller: choose a usable role administrator and upgrade authority; initialization permits the zero address"
        );
        string[] memory bindings = new string[](1);
        bindings[0] = "admin";
        variant.initPlan = RecipeSpecLib.introspected(
            RecipeSpecLib.leaf("PythEntropyAdapterInit", "init(address)", variant.inputs, bindings), true
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
        variant.conditions[0] =
            "caller: configure the Entropy contract and provider after initialization; a zero provider selects its default";
        variant.conditions[1] =
        "caller: authenticate external service configuration; this recipe does not verify live providers";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] =
            RecipeSpecLib.deploymentContext("DeployPythEntropyAdapter", "run(address)", variant, "buildCuts(admin)");
    }

    /// @notice Deploys a Pyth Entropy diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The entropy admin.
    /// @return entropy The deployed entropy diamond address.
    function run(address admin) external returns (address entropy) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        entropy = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
