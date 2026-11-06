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
import {StarknetGatewayAdapter} from "@lattice/crosschain/starknet/StarknetGatewayAdapter.sol";
import {StarknetGatewayAdapterInit} from "@lattice/crosschain/starknet/StarknetGatewayAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployStarknetGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Starknet L1 <-> L2 connector diamond (Ethereum L1 only): `ERC165Facet`
///         + `AccessControl` + `StarknetGatewayAdapter` + {StarknetGatewayAdapterInit}. The ONE source of truth
///         for what a Starknet adapter diamond is, shared by production (`run --broadcast`) and the facet tests
///         (which build on {buildCuts}). `AccessControl` is part of the base recipe because the L2 handler /
///         trusted-sender setters are `DEFAULT_ADMIN_ROLE`-gated. The Starknet core and expected chain
///         reference are wired at init; L2 targets (+ their `l1_handler` selectors) and trusted L2 senders are
///         registered by the admin AFTER deploy (verify them).
contract DeployStarknetGatewayAdapter is BaseDeploy {
    /// @notice Builds the Starknet adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin                  The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param starknetCore           The Starknet core (`StarknetMessaging`) contract on this chain.
    /// @param expectedChainReference The ERC-7930 chain reference to accept (e.g. `SN_MAIN` UTF-8 bytes).
    /// @return cuts         The facet cuts (ERC165 + AccessControl + StarknetGatewayAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init         The {MultiInit} running {StarknetGatewayAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address starknetCore, bytes memory expectedChainReference)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("StarknetGatewayAdapterInit"),
            abi.encodeCall(StarknetGatewayAdapterInit.init, (admin, starknetCore, expectedChainReference))
        );
    }

    /// @notice Deploys a Starknet adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin                  The adapter admin.
    /// @param starknetCore           The Starknet core (`StarknetMessaging`) contract on this chain.
    /// @param expectedChainReference The ERC-7930 chain reference to accept (e.g. `SN_MAIN` UTF-8 bytes).
    /// @return adapter The deployed Starknet adapter diamond address.
    function run(address admin, address starknetCore, bytes memory expectedChainReference)
        external
        returns (address adapter)
    {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            buildCuts(admin, starknetCore, expectedChainReference);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployStarknetGatewayAdapter: unknown variant");
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("StarknetGatewayAdapter");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical builder variants and exact ordered initializer calls as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec(
            "DeployStarknetGatewayAdapter", "script/base/crosschain/DeployStarknetGatewayAdapter.s.sol", 1
        );
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployStarknetGatewayAdapter:buildCuts(address,address,bytes)";
        variant.buildSignature = "buildCuts(address,address,bytes)";
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
            "starknetCore",
            "address",
            "Starknet-L1-messaging-core",
            "target-configured-starknet-core",
            "enforced: nonzero; caller authenticates the local Starknet messaging contract"
        );
        variant.inputs[2] = RecipeParameter(
            "expectedChainReference",
            "bytes",
            "ERC7930-Starknet-chain-reference-bytes",
            "mock-starknet-chain-reference-bytes",
            "enforced: nonempty; caller supplies the target Starknet chain reference, not an EVM chain ID"
        );
        RecipeParameter[] memory parameters = new RecipeParameter[](3);
        parameters[0] = variant.inputs[0];
        parameters[1] = variant.inputs[1];
        parameters[2] = variant.inputs[2];
        string[] memory bindings = new string[](3);
        bindings[0] = "admin";
        bindings[1] = "starknetCore";
        bindings[2] = "expectedChainReference";
        RecipeInitStep[] memory module =
            RecipeSpecLib.leaf("StarknetGatewayAdapterInit", "init(address,address,bytes)", parameters, bindings);
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
            "StarknetGatewayAdapter",
            "inboundMessageVerifier",
            "starknetCore",
            "the core consumes authenticated L2 messages addressed to this diamond"
        );
        variant.conditions = new string[](1);
        variant.conditions[0] =
        "caller: configure L2 handlers, l1_handler selectors and trusted L2 senders after deployment";
        result.variants[0] = variant;
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployStarknetGatewayAdapter",
            "run(address,address,bytes)",
            variant,
            "buildCuts(admin,starknetCore,expectedChainReference)"
        );
    }
}
