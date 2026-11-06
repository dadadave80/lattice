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
import {CCIPGatewayAdapter} from "@lattice/crosschain/chainlink/CCIPGatewayAdapter.sol";
import {CCIPGatewayAdapterInit} from "@lattice/crosschain/chainlink/CCIPGatewayAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployCCIPGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Chainlink CCIP gateway-adapter diamond: `ERC165Facet` + `AccessControl` +
///         `CCIPGatewayAdapter` + {CCIPGatewayAdapterInit}. The ONE source of truth for what a CCIP adapter diamond
///         is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because every chain-selector / remote-gateway / destination /
///         fee-token setter is `DEFAULT_ADMIN_ROLE`-gated. The CCIP router and fee token are wired at init time.
contract DeployCCIPGatewayAdapter is BaseDeploy {
    /// @notice Builds the CCIP adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param router The CCIP router the adapter dispatches to and accepts deliveries from.
    /// @param feeToken The initial CCIP fee token (`address(0)` = native gas).
    /// @return cuts The facet cuts (ERC165 + AccessControl + CCIPGatewayAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {CCIPGatewayAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address router, address feeToken)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("CCIPGatewayAdapterInit"), abi.encodeCall(CCIPGatewayAdapterInit.init, (admin, router, feeToken))
        );
    }

    /// @notice Deploys a CCIP adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The adapter admin.
    /// @param router The CCIP router.
    /// @param feeToken The initial CCIP fee token (`address(0)` = native gas).
    /// @return adapter The deployed CCIP adapter diamond address.
    function run(address admin, address router, address feeToken) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, router, feeToken);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployCCIPGatewayAdapter: unknown variant");
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("CCIPGatewayAdapter");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical builder variants and exact ordered initializer calls as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result =
            RecipeSpecLib.spec("DeployCCIPGatewayAdapter", "script/base/crosschain/DeployCCIPGatewayAdapter.s.sol", 1);
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployCCIPGatewayAdapter:buildCuts(address,address,address)";
        variant.buildSignature = "buildCuts(address,address,address)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Single;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](3);
        variant.inputs[0] = RecipeParameter(
            "admin",
            "address",
            "account",
            "0x00000000000000000000000000000000000000ad",
            "caller: choose a usable role and upgrade administrator; initialization permits the zero address"
        );
        variant.inputs[1] = RecipeParameter(
            "router",
            "address",
            "CCIP-router",
            "target-configured-ccip-router",
            "caller: authenticate the local CCIP router; initialization does not check nonzero or code"
        );
        variant.inputs[2] = RecipeParameter(
            "feeToken",
            "address",
            "CCIP-fee-token-or-native",
            "0x0000000000000000000000000000000000000000",
            "zero selects native fees; caller verifies any nonzero fee token is supported by the router"
        );
        RecipeParameter[] memory parameters = new RecipeParameter[](3);
        parameters[0] = variant.inputs[0];
        parameters[1] = variant.inputs[1];
        parameters[2] = variant.inputs[2];
        string[] memory bindings = new string[](3);
        bindings[0] = "admin";
        bindings[1] = "router";
        bindings[2] = "feeToken";
        RecipeInitStep[] memory module =
            RecipeSpecLib.leaf("CCIPGatewayAdapterInit", "init(address,address,address)", parameters, bindings);
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
            "CCIPGatewayAdapter",
            "inboundRouter",
            "router",
            "only the configured router may invoke ccipReceive; trusted remote sender checks also apply"
        );
        variant.conditions = new string[](1);
        variant.conditions[0] =
        "caller: configure chain selectors, trusted remote gateways and supported destinations before messaging";
        result.variants[0] = variant;
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployCCIPGatewayAdapter", "run(address,address,address)", variant, "buildCuts(admin,router,feeToken)"
        );
    }
}
