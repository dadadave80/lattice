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
import {ERC2981} from "@lattice/tokens/ERC2981/ERC2981.sol";
import {ERC2981Init} from "@lattice/tokens/ERC2981/ERC2981Init.sol";

/// @title DeployERC2981
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-2981 royalty diamond: `ERC165Facet` + `AccessControl` + `ERC2981`
///         + {ERC2981Init}. The ONE source of truth for what a royalty diamond is, shared by production
///         (`run --broadcast`) and the facet tests (which build on {buildCuts}). `AccessControl` is part of the
///         base recipe because every royalty setter is `DEFAULT_ADMIN_ROLE`-gated.
contract DeployERC2981 is BaseDeploy {
    /// @notice Builds the ERC-2981 royalty diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the royalty setters).
    /// @return cuts The facet cuts (ERC165 + AccessControl + ERC2981 + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {ERC2981Init} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) =
            _withUpgradeableIntrospection(_init("ERC2981Init"), abi.encodeCall(ERC2981Init.init, (admin)));
    }

    function _cutPlan(uint256) internal pure returns (RecipeFacet[] memory facets) {
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("ERC2981");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice The royalty cut plan, ordered initialization and actual role grant as script-only data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC2981", "script/base/tokens/DeployERC2981.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployERC2981:buildCuts(address)";
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
            "caller: choose a usable royalty and upgrade administrator; initialization permits the zero address"
        );
        RecipeParameter[] memory parameters = new RecipeParameter[](1);
        parameters[0] = RecipeParameter(
            "admin", "address", variant.inputs[0].unit, variant.inputs[0].example, variant.inputs[0].rule
        );
        string[] memory bindings = new string[](1);
        bindings[0] = "admin";
        variant.initPlan =
            RecipeSpecLib.introspected(RecipeSpecLib.leaf("ERC2981Init", "init(address)", parameters, bindings), true);
        variant.authorities = new RecipeAuthority[](1);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "royalty configuration, role administration and diamondCut"
        );
        variant.conditions = new string[](2);
        variant.conditions[0] =
            "the bundle initializes AccessControl then ERC2981; royalty recipients and fee fractions require separate configuration after deployment";
        variant.conditions[1] =
            "this recipe routes the royalty surface only, with no NFT ownership, transfer or mint surface and no mint role grant";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] =
            RecipeSpecLib.deploymentContext("DeployERC2981", "run(address)", variant, "buildCuts(admin)");
    }

    /// @notice Deploys an ERC-2981 royalty diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The royalty admin.
    /// @return royalty The deployed royalty diamond address.
    function run(address admin) external returns (address royalty) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        royalty = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
