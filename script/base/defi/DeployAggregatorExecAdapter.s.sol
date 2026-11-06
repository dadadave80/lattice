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
import {Receive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AggregatorExecAdapter} from "@lattice/defi/AggregatorExecAdapter.sol";
import {AggregatorExecAdapterInit} from "@lattice/defi/AggregatorExecAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployAggregatorExecAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a generic swap/bridge execution diamond: `ERC165Facet` + `AccessControl` +
///         `AggregatorExecAdapter` + {AggregatorExecAdapterInit}. The ONE source of truth for what an aggregator
///         execution diamond is, shared by production (`run --broadcast`) and the facet tests (which build on
///         {buildCuts}). `AccessControl` is part of the base recipe because the `(aggregator, selector)`
///         allow-list setter is `DEFAULT_ADMIN_ROLE`-gated. The aggregator allow-list is populated by the admin
///         AFTER deploy (e.g. allow-listing the LI.FI Diamond's swap/bridge selectors). `Receive` is part of it
///         because an aggregator pays native swap output and unspent `msg.value` back with a plain send, which
///         {AggregatorExecAdapter} then sweeps to the caller.
contract DeployAggregatorExecAdapter is BaseDeploy {
    /// @notice Builds the aggregator execution diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the allow-list setter).
    /// @return cuts         The facet cuts (ERC165 + AccessControl + AggregatorExecAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init         The {MultiInit} running {AggregatorExecAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("AggregatorExecAdapterInit"), abi.encodeCall(AggregatorExecAdapterInit.init, (admin))
        );
    }

    /// @notice Deploys an aggregator execution diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The adapter admin.
    /// @return adapter The deployed aggregator execution diamond address.
    function run(address admin) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployAggregatorExecAdapter: unknown variant");
        facets = new RecipeFacet[](6);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("AggregatorExecAdapter");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
        facets[5] = RecipePlanLib.all("Receive");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cut plan, typed initializer tree and deployment inputs as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result =
            RecipeSpecLib.spec("DeployAggregatorExecAdapter", "script/base/defi/DeployAggregatorExecAdapter.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployAggregatorExecAdapter:buildCuts(address)";
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
            "enforced: nonzero; caller chooses a trusted allow-list and upgrade administrator"
        );
        string[] memory bindings = new string[](1);
        bindings[0] = "admin";
        variant.initPlan = RecipeSpecLib.introspected(
            RecipeSpecLib.leaf("AggregatorExecAdapterInit", "init(address)", variant.inputs, bindings), true
        );
        variant.authorities = new RecipeAuthority[](1);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "aggregator/selector allow-list administration, role administration and diamondCut"
        );
        variant.conditions = new string[](2);
        variant.conditions[0] =
            "caller: authenticate and allow-list each aggregator/selector pair after deployment; initialization installs no aggregator permissions";
        variant.conditions[1] =
            "Receive remains present for native swap output and refunds; execution sweeps the applicable output back to its caller";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] =
            RecipeSpecLib.deploymentContext("DeployAggregatorExecAdapter", "run(address)", variant, "buildCuts(admin)");
    }
}
