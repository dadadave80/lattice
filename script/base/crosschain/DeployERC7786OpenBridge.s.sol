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
import {ERC7786OpenBridge} from "@lattice/crosschain/ERC7786OpenBridge.sol";
import {ERC7786OpenBridgeInit} from "@lattice/crosschain/ERC7786OpenBridgeInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployERC7786OpenBridge
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-7786 open-bridge diamond: `ERC165Facet` + `AccessControl` +
///         `ERC7786OpenBridge` + {ERC7786OpenBridgeInit}. The ONE source of truth for what an open-bridge diamond
///         is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because the gateway-set, threshold and remote-bridge setters
///         are `DEFAULT_ADMIN_ROLE`-gated. The bridge is gateway-agnostic, so the gateway set is configured
///         post-deploy by the admin rather than at init, in this order: `addGateway` (each gateway), `setThreshold`,
///         then `registerRemoteBridge`. `registerRemoteBridge` reverts while the threshold is 0, and the bridge
///         never executes an inbound message at threshold 0.
contract DeployERC7786OpenBridge is BaseDeploy {
    /// @notice Builds the open-bridge diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the gateway set, threshold and remotes).
    /// @return cuts The facet cuts (ERC165 + AccessControl + ERC7786OpenBridge + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {ERC7786OpenBridgeInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("ERC7786OpenBridgeInit"), abi.encodeCall(ERC7786OpenBridgeInit.init, (admin))
        );
    }

    /// @notice Deploys an open-bridge diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The bridge admin.
    /// @return bridge The deployed open-bridge diamond address.
    function run(address admin) external returns (address bridge) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        bridge = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployERC7786OpenBridge: unknown variant");
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("ERC7786OpenBridge");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical builder variants and exact ordered initializer calls as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result =
            RecipeSpecLib.spec("DeployERC7786OpenBridge", "script/base/crosschain/DeployERC7786OpenBridge.s.sol", 1);
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployERC7786OpenBridge:buildCuts(address)";
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
            RecipeSpecLib.leaf("ERC7786OpenBridgeInit", "init(address)", parameters, bindings);
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
        variant.conditions[0] = "caller: configure approved gateways and the attestation threshold after deployment";
        result.variants[0] = variant;
        result.deploymentContexts[0] =
            RecipeSpecLib.deploymentContext("DeployERC7786OpenBridge", "run(address)", variant, "buildCuts(admin)");
    }
}
