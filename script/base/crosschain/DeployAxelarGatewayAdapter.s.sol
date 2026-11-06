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
import {AxelarGatewayAdapter} from "@lattice/crosschain/axelar/AxelarGatewayAdapter.sol";
import {AxelarGatewayAdapterInit} from "@lattice/crosschain/axelar/AxelarGatewayAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployAxelarGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an Axelar gateway-adapter diamond: `ERC165Facet` + `AccessControl` +
///         `AxelarGatewayAdapter` + {AxelarGatewayAdapterInit}. The ONE source of truth for what an Axelar adapter
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because every chain-equivalence / remote-gateway setter is
///         `DEFAULT_ADMIN_ROLE`-gated. The Axelar gateway is wired at init time.
contract DeployAxelarGatewayAdapter is BaseDeploy {
    /// @notice Builds the Axelar adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param gateway The Axelar gateway the adapter dispatches to and validates inbound calls with.
    /// @return cuts The facet cuts (ERC165 + AccessControl + AxelarGatewayAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {AxelarGatewayAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address gateway)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("AxelarGatewayAdapterInit"), abi.encodeCall(AxelarGatewayAdapterInit.init, (admin, gateway))
        );
    }

    /// @notice Deploys an Axelar adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The adapter admin.
    /// @param gateway The Axelar gateway.
    /// @return adapter The deployed Axelar adapter diamond address.
    function run(address admin, address gateway) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, gateway);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployAxelarGatewayAdapter: unknown variant");
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("AxelarGatewayAdapter");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical builder variants and exact ordered initializer calls as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec(
            "DeployAxelarGatewayAdapter", "script/base/crosschain/DeployAxelarGatewayAdapter.s.sol", 1
        );
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployAxelarGatewayAdapter:buildCuts(address,address)";
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
            "gateway",
            "address",
            "Axelar-gateway",
            "target-configured-axelar-gateway",
            "caller: authenticate the local Axelar gateway; initialization does not check nonzero or code"
        );
        RecipeParameter[] memory parameters = new RecipeParameter[](2);
        parameters[0] = variant.inputs[0];
        parameters[1] = variant.inputs[1];
        string[] memory bindings = new string[](2);
        bindings[0] = "admin";
        bindings[1] = "gateway";
        RecipeInitStep[] memory module =
            RecipeSpecLib.leaf("AxelarGatewayAdapterInit", "init(address,address)", parameters, bindings);
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
            "AxelarGatewayAdapter",
            "gatewayApprovalAuthority",
            "gateway",
            "validates approved inbound contract calls before trusted-origin checks"
        );
        variant.conditions = new string[](1);
        variant.conditions[0] = "caller: configure chain-name equivalences and trusted remote gateways after deployment";
        result.variants[0] = variant;
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployAxelarGatewayAdapter", "run(address,address)", variant, "buildCuts(admin,gateway)"
        );
    }
}
