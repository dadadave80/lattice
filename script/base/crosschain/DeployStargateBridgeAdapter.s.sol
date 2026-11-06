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
    RecipeInitStep,
    RecipeParameter,
    RecipeProxyKind,
    RecipeSeam,
    RecipeSpec,
    RecipeVariant
} from "@lattice-script/lib/RecipeSpec.sol";
import {RecipeSpecLib} from "@lattice-script/lib/RecipeSpecLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {StargateBridgeAdapter} from "@lattice/crosschain/layerzero/StargateBridgeAdapter.sol";
import {StargateBridgeAdapterInit} from "@lattice/crosschain/layerzero/StargateBridgeAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployStargateBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Stargate v2 token-bridge diamond: `ERC165Facet` + `AccessControl` +
///         `StargateBridgeAdapter` + {StargateBridgeAdapterInit}. The ONE source of truth for what a Stargate
///         adapter diamond is, shared by production (`run --broadcast`) and the facet tests (which build on
///         {buildCuts}). `AccessControl` is part of the base recipe because every eid / pool registration is
///         `DEFAULT_ADMIN_ROLE`-gated. No protocol addresses are wired at init: the chainId ⇄ eid map and the
///         per-token pools (ERC-20 pools ONLY — never `StargatePoolNative`) are registered by the admin AFTER
///         deploy (verify them).
contract DeployStargateBridgeAdapter is BaseDeploy {
    /// @notice Builds the Stargate adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @return cuts         The facet cuts (ERC165 + AccessControl + StargateBridgeAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init         The {MultiInit} running {StargateBridgeAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("StargateBridgeAdapterInit"), abi.encodeCall(StargateBridgeAdapterInit.init, (admin))
        );
    }

    /// @notice Deploys a Stargate adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The adapter admin.
    /// @return adapter The deployed Stargate adapter diamond address.
    function run(address admin) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployStargateBridgeAdapter: unknown variant");
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("StargateBridgeAdapter");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical builder variants and exact ordered initializer calls as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec(
            "DeployStargateBridgeAdapter", "script/base/crosschain/DeployStargateBridgeAdapter.s.sol", 1
        );
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployStargateBridgeAdapter:buildCuts(address)";
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
            "caller: choose a usable role and upgrade administrator; initialization permits the zero address"
        );
        RecipeParameter[] memory parameters = new RecipeParameter[](1);
        parameters[0] = variant.inputs[0];
        string[] memory bindings = new string[](1);
        bindings[0] = "admin";
        RecipeInitStep[] memory module =
            RecipeSpecLib.leaf("StargateBridgeAdapterInit", "init(address)", parameters, bindings);
        variant.initPlan = RecipeSpecLib.introspected(module, true);
        variant.authorities = new RecipeAuthority[](1);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "module configuration, role administration and diamondCut"
        );
        variant.conditions = new string[](1);
        variant.conditions[0] =
            "caller: configure endpoint IDs and verified ERC20 Stargate pools after deployment; native-token pools are unsupported";
        result.variants[0] = variant;
        result.deploymentContexts[0] =
            RecipeSpecLib.deploymentContext("DeployStargateBridgeAdapter", "run(address)", variant, "buildCuts(admin)");
    }
}
