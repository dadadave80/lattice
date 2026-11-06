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
import {ZetaChainGatewayAdapter} from "@lattice/crosschain/zetachain/ZetaChainGatewayAdapter.sol";
import {ZetaChainGatewayAdapterInit} from "@lattice/crosschain/zetachain/ZetaChainGatewayAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployZetaChainGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a ZetaChain `GatewayEVM` gateway-adapter diamond: `ERC165Facet` +
///         `AccessControl` + `ZetaChainGatewayAdapter` + {ZetaChainGatewayAdapterInit}. The ONE source of truth
///         for what such an adapter diamond is, shared by production (`run --broadcast`) and the facet tests
///         (which build on {buildCuts}). `AccessControl` is part of the base recipe because the gateway/remote/
///         revert-gas setters are `DEFAULT_ADMIN_ROLE`-gated. The `GatewayEVM` is a DEPLOYED contract (per-
///         connected-chain address), passed as a ctor arg — not a fixed predeploy.
contract DeployZetaChainGatewayAdapter is BaseDeploy {
    /// @notice Builds the adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param gateway The ZetaChain `GatewayEVM` the adapter dispatches to / accepts `onCall` from.
    /// @param hubChainId The hub chainId whose ZEVM universal app terminates the route.
    /// @param hubRemoteApp The trusted ZEVM universal app (hub) for `hubChainId`.
    /// @param defaultOnRevertGasLimit The default `onRevertGasLimit` used to build per-message `RevertOptions`.
    /// @return cuts The facet cuts (ERC165 + AccessControl + ZetaChainGatewayAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {ZetaChainGatewayAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(
        address admin,
        address gateway,
        uint256 hubChainId,
        address hubRemoteApp,
        uint256 defaultOnRevertGasLimit
    ) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("ZetaChainGatewayAdapterInit"),
            abi.encodeCall(
                ZetaChainGatewayAdapterInit.init, (admin, gateway, hubChainId, hubRemoteApp, defaultOnRevertGasLimit)
            )
        );
    }

    /// @notice Deploys the adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The adapter admin.
    /// @param gateway The ZetaChain `GatewayEVM`.
    /// @param hubChainId The hub chainId.
    /// @param hubRemoteApp The trusted ZEVM universal app (hub).
    /// @param defaultOnRevertGasLimit The default revert gas limit.
    /// @return adapter The deployed adapter diamond address.
    function run(
        address admin,
        address gateway,
        uint256 hubChainId,
        address hubRemoteApp,
        uint256 defaultOnRevertGasLimit
    ) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            buildCuts(admin, gateway, hubChainId, hubRemoteApp, defaultOnRevertGasLimit);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployZetaChainGatewayAdapter: unknown variant");
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("ZetaChainGatewayAdapter");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical builder variants and exact ordered initializer calls as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec(
            "DeployZetaChainGatewayAdapter", "script/base/crosschain/DeployZetaChainGatewayAdapter.s.sol", 1
        );
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployZetaChainGatewayAdapter:buildCuts(address,address,uint256,address,uint256)";
        variant.buildSignature = "buildCuts(address,address,uint256,address,uint256)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Single;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](5);
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
            "ZetaChain-GatewayEVM",
            "target-configured-zeta-gateway",
            "enforced: nonzero; caller authenticates the connected-chain GatewayEVM deployment"
        );
        variant.inputs[2] = RecipeParameter(
            "hubChainId",
            "uint256",
            "EVM-hub-chain-id",
            "mock-hub-chain-id",
            "enforced: nonzero; caller supplies the configured ZEVM hub chain ID"
        );
        variant.inputs[3] = RecipeParameter(
            "hubRemoteApp",
            "address",
            "ZEVM-hub-remote-app",
            "target-configured-hub-remote-app",
            "enforced: nonzero and uniquely registered by chain and app; caller authenticates the trusted hub application"
        );
        variant.inputs[4] = RecipeParameter(
            "defaultOnRevertGasLimit",
            "uint256",
            "gas",
            "200000",
            "initialization accepts any value; sending without an override requires a default at most 2000000"
        );
        RecipeParameter[] memory parameters = new RecipeParameter[](5);
        parameters[0] = variant.inputs[0];
        parameters[1] = variant.inputs[1];
        parameters[2] = variant.inputs[2];
        parameters[3] = variant.inputs[3];
        parameters[4] = variant.inputs[4];
        string[] memory bindings = new string[](5);
        bindings[0] = "admin";
        bindings[1] = "gateway";
        bindings[2] = "hubChainId";
        bindings[3] = "hubRemoteApp";
        bindings[4] = "defaultOnRevertGasLimit";
        RecipeInitStep[] memory module = RecipeSpecLib.leaf(
            "ZetaChainGatewayAdapterInit", "init(address,address,uint256,address,uint256)", parameters, bindings
        );
        variant.initPlan = RecipeSpecLib.introspected(module, true);
        variant.authorities = new RecipeAuthority[](3);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "module configuration, role administration and diamondCut"
        );
        variant.authorities[1] = RecipeSpecLib.externalAuthority(
            "ZetaChainGatewayAdapter", "inboundGateway", "gateway", "only the configured GatewayEVM may invoke onCall"
        );
        variant.authorities[2] = RecipeSpecLib.externalAuthority(
            "ZetaChainGatewayAdapter",
            "initialTrustedHubApp",
            "hubRemoteApp",
            "the initial trusted origin app registered for hubChainId"
        );
        variant.conditions = new string[](2);
        variant.conditions[0] =
            "caller: authenticate the configured gateway and hub remote app; initialization registers exactly the supplied hub route";
        variant.conditions[1] =
            "sendMessage accepts one canonical revertOptions attribute; both recovery addresses must be nonzero, callOnRevert=false, gas<=2000000, combined encoded message/revert data<=2880 bytes; no attribute uses caller addresses, empty revert data and the configured default gas";
        result.variants[0] = variant;
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployZetaChainGatewayAdapter",
            "run(address,address,uint256,address,uint256)",
            variant,
            "buildCuts(admin,gateway,hubChainId,hubRemoteApp,defaultOnRevertGasLimit)"
        );
    }
}
