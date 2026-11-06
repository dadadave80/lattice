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
import {HyperbridgeGatewayAdapter} from "@lattice/crosschain/hyperbridge/HyperbridgeGatewayAdapter.sol";
import {HyperbridgeGatewayAdapterInit} from "@lattice/crosschain/hyperbridge/HyperbridgeGatewayAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployHyperbridgeGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Hyperbridge gateway-adapter diamond: `ERC165Facet` + `AccessControl` +
///         `HyperbridgeGatewayAdapter` + {HyperbridgeGatewayAdapterInit}. The ONE source of truth for what a
///         Hyperbridge adapter diamond is, shared by production (`run --broadcast`) and the facet tests (which
///         build on {buildCuts}). `AccessControl` is part of the base recipe because every state machine /
///         remote-module / timeout setter is `DEFAULT_ADMIN_ROLE`-gated. The Hyperbridge IsmpHost is wired at
///         init time; fees are charged in the host's ERC-20 `feeToken()` read live at send time, so nothing
///         fee-related is deployed here.
contract DeployHyperbridgeGatewayAdapter is BaseDeploy {
    /// @notice Builds the Hyperbridge adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param host  The Hyperbridge IsmpHost the adapter dispatches to and accepts module callbacks from.
    /// @return cuts The facet cuts (ERC165 + AccessControl + HyperbridgeGatewayAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {HyperbridgeGatewayAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address host)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("HyperbridgeGatewayAdapterInit"), abi.encodeCall(HyperbridgeGatewayAdapterInit.init, (admin, host))
        );
    }

    /// @notice Deploys a Hyperbridge adapter diamond (broadcasting entrypoint for `forge script ...
    ///         --broadcast`).
    /// @param admin The adapter admin.
    /// @param host  The Hyperbridge IsmpHost.
    /// @return adapter The deployed Hyperbridge adapter diamond address.
    function run(address admin, address host) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, host);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployHyperbridgeGatewayAdapter: unknown variant");
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("HyperbridgeGatewayAdapter");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical builder variants and exact ordered initializer calls as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec(
            "DeployHyperbridgeGatewayAdapter", "script/base/crosschain/DeployHyperbridgeGatewayAdapter.s.sol", 1
        );
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployHyperbridgeGatewayAdapter:buildCuts(address,address)";
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
            "caller: choose a usable role and upgrade administrator; initialization permits the zero address"
        );
        variant.inputs[1] = RecipeParameter(
            "host",
            "address",
            "Hyperbridge-host",
            "target-configured-hyperbridge-host",
            "enforced: nonzero; caller authenticates the host implementation and supported state-machine routes"
        );
        RecipeParameter[] memory parameters = new RecipeParameter[](2);
        parameters[0] = variant.inputs[0];
        parameters[1] = variant.inputs[1];
        string[] memory bindings = new string[](2);
        bindings[0] = "admin";
        bindings[1] = "host";
        RecipeInitStep[] memory module =
            RecipeSpecLib.leaf("HyperbridgeGatewayAdapterInit", "init(address,address)", parameters, bindings);
        variant.initPlan = RecipeSpecLib.introspected(module, true);
        variant.authorities = new RecipeAuthority[](2);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "module configuration, role administration and diamondCut"
        );
        variant.authorities[1] = RecipeSpecLib.externalAuthority(
            "HyperbridgeGatewayAdapter",
            "inboundHost",
            "host",
            "only the configured host may invoke authenticated post and timeout callbacks"
        );
        variant.conditions = new string[](1);
        variant.conditions[0] =
        "caller: configure state-machine equivalences, trusted remote gateways and destinations before messaging";
        result.variants[0] = variant;
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployHyperbridgeGatewayAdapter", "run(address,address)", variant, "buildCuts(admin,host)"
        );
    }
}
