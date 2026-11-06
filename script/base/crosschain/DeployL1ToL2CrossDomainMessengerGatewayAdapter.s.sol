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
import {
    L1ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice/crosschain/optimism/L1ToL2CrossDomainMessengerGatewayAdapter.sol";
import {
    L1ToL2CrossDomainMessengerGatewayAdapterInit
} from "@lattice/crosschain/optimism/L1ToL2CrossDomainMessengerGatewayAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployL1ToL2CrossDomainMessengerGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a canonical OP Stack L1<->L2 `CrossDomainMessenger` gateway-adapter diamond:
///         `ERC165Facet` + `AccessControl` + `L1ToL2CrossDomainMessengerGatewayAdapter` +
///         {L1ToL2CrossDomainMessengerGatewayAdapterInit}. The ONE source of truth for what such an adapter
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because the counterpart/min-gas setters are
///         `DEFAULT_ADMIN_ROLE`-gated. Unlike the CCIP/LayerZero recipes there is no endpoint/router arg — the
///         messenger is the fixed predeploy constant.
contract DeployL1ToL2CrossDomainMessengerGatewayAdapter is BaseDeploy {
    /// @notice Builds the adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin              The address granted `DEFAULT_ADMIN_ROLE` (controls the setters).
    /// @param counterpartChainId The paired-domain chain id.
    /// @param counterpartAdapter The sibling adapter on the paired domain (must be non-zero).
    /// @param minGasLimit        The `minGasLimit` the messenger relays outbound messages with.
    /// @return cuts The facet cuts (ERC165 + AccessControl + L1ToL2CrossDomainMessengerGatewayAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {L1ToL2CrossDomainMessengerGatewayAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, uint256 counterpartChainId, address counterpartAdapter, uint32 minGasLimit)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("L1ToL2CrossDomainMessengerGatewayAdapterInit"),
            abi.encodeCall(
                L1ToL2CrossDomainMessengerGatewayAdapterInit.init,
                (admin, counterpartChainId, counterpartAdapter, minGasLimit)
            )
        );
    }

    /// @notice Deploys the adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin              The adapter admin.
    /// @param counterpartChainId The paired-domain chain id.
    /// @param counterpartAdapter The sibling adapter on the paired domain.
    /// @param minGasLimit        The `minGasLimit` the messenger relays outbound messages with.
    /// @return adapter The deployed adapter diamond address.
    function run(address admin, uint256 counterpartChainId, address counterpartAdapter, uint32 minGasLimit)
        external
        returns (address adapter)
    {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            buildCuts(admin, counterpartChainId, counterpartAdapter, minGasLimit);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployL1ToL2CrossDomainMessengerGatewayAdapter: unknown variant");
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("L1ToL2CrossDomainMessengerGatewayAdapter");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical builder variants and exact ordered initializer calls as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec(
            "DeployL1ToL2CrossDomainMessengerGatewayAdapter",
            "script/base/crosschain/DeployL1ToL2CrossDomainMessengerGatewayAdapter.s.sol",
            1
        );
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployL1ToL2CrossDomainMessengerGatewayAdapter:buildCuts(address,uint256,address,uint32)";
        variant.buildSignature = "buildCuts(address,uint256,address,uint32)";
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
            "counterpartChainId",
            "uint256",
            "EVM-chain-id",
            "mock-counterpart-chain-id",
            "caller: supply the actual counterpart EVM chain ID; initialization permits zero"
        );
        variant.inputs[2] = RecipeParameter(
            "counterpartAdapter",
            "address",
            "remote-adapter",
            "target-configured-counterpart-adapter",
            "enforced: nonzero; caller authenticates the counterpart adapter on the specified chain"
        );
        variant.inputs[3] = RecipeParameter(
            "minGasLimit",
            "uint32",
            "gas",
            "200000",
            "enforced: greater than zero; caller provisions enough relay gas for the recipient handshake"
        );
        RecipeParameter[] memory parameters = new RecipeParameter[](4);
        parameters[0] = variant.inputs[0];
        parameters[1] = variant.inputs[1];
        parameters[2] = variant.inputs[2];
        parameters[3] = variant.inputs[3];
        string[] memory bindings = new string[](4);
        bindings[0] = "admin";
        bindings[1] = "counterpartChainId";
        bindings[2] = "counterpartAdapter";
        bindings[3] = "minGasLimit";
        RecipeInitStep[] memory module = RecipeSpecLib.leaf(
            "L1ToL2CrossDomainMessengerGatewayAdapterInit", "init(address,uint256,address,uint32)", parameters, bindings
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
            "L1ToL2CrossDomainMessengerGatewayAdapter",
            "inboundMessenger",
            "L2_CROSS_DOMAIN_MESSENGER",
            "fixed messenger authenticates the cross-domain sender"
        );
        variant.authorities[2] = RecipeSpecLib.externalAuthority(
            "L1ToL2CrossDomainMessengerGatewayAdapter",
            "initialTrustedCounterpart",
            "counterpartAdapter",
            "the initial authenticated cross-domain sender for counterpartChainId"
        );
        variant.conditions = new string[](2);
        variant.conditions[0] =
            "caller: verify the target chain supports the fixed L2_CROSS_DOMAIN_MESSENGER at 0x4200000000000000000000000000000000000007";
        variant.conditions[1] =
            "the counterpart chain, counterpart adapter and minimum relay gas are initialized from the explicit builder inputs";
        result.variants[0] = variant;
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployL1ToL2CrossDomainMessengerGatewayAdapter",
            "run(address,uint256,address,uint32)",
            variant,
            "buildCuts(admin,counterpartChainId,counterpartAdapter,minGasLimit)"
        );
    }
}
