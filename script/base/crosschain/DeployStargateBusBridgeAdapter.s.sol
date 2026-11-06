// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {MultiInit} from "@diamond/initializers/MultiInit.sol";
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
import {StargateBusBridgeAdapter} from "@lattice/crosschain/layerzero/StargateBusBridgeAdapter.sol";
import {StargateBusBridgeAdapterInit} from "@lattice/crosschain/layerzero/StargateBusBridgeAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployStargateBusBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Optional ERC20 bus + taxi recipe; the original taxi-only recipe stays unchanged.
/// @dev The bus path requires the exact quote and returns a queue ticket, not destination completion.
///      Configure trusted pools/eids after deployment; no native pool/drop, compose, drive or cancel facade.
contract DeployStargateBusBridgeAdapter is BaseDeploy {
    /// @notice Builds the Stargate adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @return cuts         Six All/Add cuts, including both distinct Stargate capabilities and upgrade authority.
    /// @return init         The {MultiInit} running base bundle, bus registration, then upgradeable introspection.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        address[] memory inits = new address[](3);
        bytes[] memory calls = new bytes[](3);
        inits[0] = _init("StargateBridgeAdapterInit");
        calls[0] = abi.encodeCall(StargateBridgeAdapterInit.init, (admin));
        inits[1] = _init("StargateBusBridgeAdapterInit");
        calls[1] = abi.encodeCall(StargateBusBridgeAdapterInit.init, ());
        inits[2] = _init("DiamondIntrospectionInit");
        calls[2] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
        init = _init("MultiInit");
        initCalldata = abi.encodeCall(MultiInit.multiInit, (inits, calls));
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
        require(variant == 0, "DeployStargateBusBridgeAdapter: unknown variant");
        facets = new RecipeFacet[](6);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("StargateBridgeAdapter");
        facets[3] = RecipePlanLib.all("StargateBusBridgeAdapter");
        facets[4] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[5] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical builder variants and exact ordered initializer calls as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec(
            "DeployStargateBusBridgeAdapter", "script/base/crosschain/DeployStargateBusBridgeAdapter.s.sol", 1
        );
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployStargateBusBridgeAdapter:buildCuts(address)";
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
        RecipeInitStep[][] memory children = new RecipeInitStep[][](3);
        children[0] = module;
        children[1] = RecipeSpecLib.emptyLeaf("StargateBusBridgeAdapterInit", "init()");
        children[2] = RecipeSpecLib.emptyLeaf("DiamondIntrospectionInit", "initUpgradeable()");
        variant.initPlan = RecipeSpecLib.wrap(children);
        variant.authorities = new RecipeAuthority[](1);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "module configuration, role administration and diamondCut"
        );
        variant.conditions = new string[](4);
        variant.conditions[0] =
            "caller: configure endpoint IDs and verified ERC20 Stargate pools with bus-enabled routes after deployment; native-token pools are unsupported";
        variant.conditions[1] =
            "enforced: bus msg.value equals the current native fare quote before token movement; no native drop or compose payload";
        variant.conditions[2] =
            "caller: retain the valid uint72 ticket (including zero) and opaque passenger bytes; enqueue has no delivery GUID and no cancellation or bounded-latency guarantee";
        variant.conditions[3] =
            "caller: monitor the upstream queue and later BusDriven GUID; a direct upstream drive requires the authenticated contiguous queued prefix and a separate fee";
        result.variants[0] = variant;
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployStargateBusBridgeAdapter", "run(address)", variant, "buildCuts(admin)"
        );
    }
}
