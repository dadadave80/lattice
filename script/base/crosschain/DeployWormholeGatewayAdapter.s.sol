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
import {WormholeGatewayAdapter} from "@lattice/crosschain/wormhole/WormholeGatewayAdapter.sol";
import {WormholeGatewayAdapterInit} from "@lattice/crosschain/wormhole/WormholeGatewayAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployWormholeGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Wormhole gateway-adapter diamond: `ERC165Facet` + `AccessControl` +
///         `WormholeGatewayAdapter` + {WormholeGatewayAdapterInit}. The ONE source of truth for what a Wormhole
///         adapter diamond is, shared by production (`run --broadcast`) and the facet tests (which build on
///         {buildCuts}). `AccessControl` is part of the base recipe because every chain-equivalence /
///         remote-gateway setter is `DEFAULT_ADMIN_ROLE`-gated. The Wormhole relayer and this chain's Wormhole
///         chain id are wired at init time.
contract DeployWormholeGatewayAdapter is BaseDeploy {
    /// @notice Builds the Wormhole adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param relayer The Wormhole relayer the adapter dispatches to and accepts deliveries from.
    /// @param wormholeChainId This chain's Wormhole chain id.
    /// @return cuts The facet cuts (ERC165 + AccessControl + WormholeGatewayAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {WormholeGatewayAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address relayer, uint16 wormholeChainId)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("WormholeGatewayAdapterInit"),
            abi.encodeCall(WormholeGatewayAdapterInit.init, (admin, relayer, wormholeChainId))
        );
    }

    /// @notice Deploys a Wormhole adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The adapter admin.
    /// @param relayer The Wormhole relayer.
    /// @param wormholeChainId This chain's Wormhole chain id.
    /// @return adapter The deployed Wormhole adapter diamond address.
    function run(address admin, address relayer, uint16 wormholeChainId) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, relayer, wormholeChainId);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployWormholeGatewayAdapter: unknown variant");
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("WormholeGatewayAdapter");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical builder variants and exact ordered initializer calls as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec(
            "DeployWormholeGatewayAdapter", "script/base/crosschain/DeployWormholeGatewayAdapter.s.sol", 1
        );
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployWormholeGatewayAdapter:buildCuts(address,address,uint16)";
        variant.buildSignature = "buildCuts(address,address,uint16)";
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
            "relayer",
            "address",
            "Wormhole-relayer",
            "target-configured-wormhole-relayer",
            "caller: authenticate the local Wormhole relayer; initialization does not check nonzero or code"
        );
        variant.inputs[2] = RecipeParameter(
            "wormholeChainId",
            "uint16",
            "Wormhole-chain-id",
            "mock-wormhole-chain-id",
            "caller: use the Wormhole uint16 chain namespace, not an EVM chain ID; initialization accepts any uint16"
        );
        RecipeParameter[] memory parameters = new RecipeParameter[](3);
        parameters[0] = variant.inputs[0];
        parameters[1] = variant.inputs[1];
        parameters[2] = variant.inputs[2];
        string[] memory bindings = new string[](3);
        bindings[0] = "admin";
        bindings[1] = "relayer";
        bindings[2] = "wormholeChainId";
        RecipeInitStep[] memory module =
            RecipeSpecLib.leaf("WormholeGatewayAdapterInit", "init(address,address,uint16)", parameters, bindings);
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
            "WormholeGatewayAdapter",
            "inboundRelayer",
            "relayer",
            "only the configured relayer may deliver; trusted source gateway checks also apply"
        );
        variant.conditions = new string[](1);
        variant.conditions[0] =
            "caller: configure Wormhole chain equivalences and trusted remote gateways after deployment; Wormhole IDs are not EVM chain IDs";
        result.variants[0] = variant;
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployWormholeGatewayAdapter",
            "run(address,address,uint16)",
            variant,
            "buildCuts(admin,relayer,wormholeChainId)"
        );
    }
}
