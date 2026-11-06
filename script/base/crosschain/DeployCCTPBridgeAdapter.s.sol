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
import {CCTPBridgeAdapter} from "@lattice/crosschain/circle/CCTPBridgeAdapter.sol";
import {CCTPBridgeAdapterInit} from "@lattice/crosschain/circle/CCTPBridgeAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployCCTPBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Circle CCTP v2 USDC token-bridge diamond: `ERC165Facet` +
///         `AccessControl` + `CCTPBridgeAdapter` + {CCTPBridgeAdapterInit}. The ONE source of truth for what a
///         CCTP adapter diamond is, shared by production (`run --broadcast`) and the facet tests (which build
///         on {buildCuts}). `AccessControl` is part of the base recipe because every chain-domain / per-domain
///         config setter is `DEFAULT_ADMIN_ROLE`-gated. The CCTP TokenMessenger, MessageTransmitter and USDC
///         are wired at init time; the CCTP domain table is registered by the admin AFTER deploy (verify it).
contract DeployCCTPBridgeAdapter is BaseDeploy {
    /// @notice Builds the CCTP adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin              The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param tokenMessenger     The deployed CCTP v2 `TokenMessengerV2`.
    /// @param messageTransmitter The deployed CCTP v2 `MessageTransmitterV2`.
    /// @param usdc               The deployed USDC token.
    /// @return cuts         The facet cuts (ERC165 + AccessControl + CCTPBridgeAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init         The {MultiInit} running {CCTPBridgeAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address tokenMessenger, address messageTransmitter, address usdc)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("CCTPBridgeAdapterInit"),
            abi.encodeCall(CCTPBridgeAdapterInit.init, (admin, tokenMessenger, messageTransmitter, usdc))
        );
    }

    /// @notice Deploys a CCTP adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin              The adapter admin.
    /// @param tokenMessenger     The deployed CCTP v2 `TokenMessengerV2`.
    /// @param messageTransmitter The deployed CCTP v2 `MessageTransmitterV2`.
    /// @param usdc               The deployed USDC token.
    /// @return adapter The deployed CCTP adapter diamond address.
    function run(address admin, address tokenMessenger, address messageTransmitter, address usdc)
        external
        returns (address adapter)
    {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            buildCuts(admin, tokenMessenger, messageTransmitter, usdc);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployCCTPBridgeAdapter: unknown variant");
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("CCTPBridgeAdapter");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical builder variants and exact ordered initializer calls as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result =
            RecipeSpecLib.spec("DeployCCTPBridgeAdapter", "script/base/crosschain/DeployCCTPBridgeAdapter.s.sol", 1);
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployCCTPBridgeAdapter:buildCuts(address,address,address,address)";
        variant.buildSignature = "buildCuts(address,address,address,address)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Single;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](4);
        variant.inputs[0] = RecipeParameter(
            "admin",
            "address",
            "account",
            "0x00000000000000000000000000000000000000ad",
            "caller: choose a usable role and upgrade administrator; initialization permits the zero address"
        );
        variant.inputs[1] = RecipeParameter(
            "tokenMessenger",
            "address",
            "CCTP-v2-TokenMessenger",
            "target-configured-token-messenger",
            "enforced: nonzero; caller authenticates the local CCTP v2 deployment and matching USDC"
        );
        variant.inputs[2] = RecipeParameter(
            "messageTransmitter",
            "address",
            "CCTP-v2-MessageTransmitter",
            "target-configured-message-transmitter",
            "enforced: nonzero; caller authenticates the local CCTP v2 deployment and matching USDC"
        );
        variant.inputs[3] = RecipeParameter(
            "usdc",
            "address",
            "USDC-token",
            "target-configured-usdc",
            "enforced: nonzero; caller authenticates the local CCTP v2 deployment and matching USDC"
        );
        RecipeParameter[] memory parameters = new RecipeParameter[](4);
        parameters[0] = variant.inputs[0];
        parameters[1] = variant.inputs[1];
        parameters[2] = variant.inputs[2];
        parameters[3] = variant.inputs[3];
        string[] memory bindings = new string[](4);
        bindings[0] = "admin";
        bindings[1] = "tokenMessenger";
        bindings[2] = "messageTransmitter";
        bindings[3] = "usdc";
        RecipeInitStep[] memory module =
            RecipeSpecLib.leaf("CCTPBridgeAdapterInit", "init(address,address,address,address)", parameters, bindings);
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
            "CCTPBridgeAdapter",
            "messageAttestationVerifier",
            "messageTransmitter",
            "the configured transmitter authenticates and consumes CCTP messages and attestations"
        );
        variant.conditions = new string[](2);
        variant.conditions[0] = "caller: configure and verify CCTP chain-domain and per-domain routes after deployment";
        variant.conditions[1] =
        "the module initializer creates one CCTPHookExecutor bound to address(this), the diamond";
        result.variants[0] = variant;
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployCCTPBridgeAdapter",
            "run(address,address,address,address)",
            variant,
            "buildCuts(admin,tokenMessenger,messageTransmitter,usdc)"
        );
    }
}
