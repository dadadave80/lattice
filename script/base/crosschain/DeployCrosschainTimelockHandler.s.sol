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
import {Receive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {CrosschainLink} from "@lattice/crosschain/CrosschainLink.sol";
import {CrosschainTimelockHandler} from "@lattice/crosschain/CrosschainTimelockHandler.sol";
import {CrosschainTimelockHandlerInit} from "@lattice/crosschain/CrosschainTimelockHandlerInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {TimelockController} from "@lattice/governance/TimelockController.sol";
import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";

/// @title DeployCrosschainTimelockHandler
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a cross-chain governance diamond: `ERC165Facet` + `AccessControl` +
///         `CrosschainLink` + `TimelockController` + `CrosschainTimelockHandler` + {CrosschainTimelockHandlerInit}.
///         The ONE source of truth for what a cross-chain timelock diamond is, shared by production
///         (`run --broadcast`) and the facet tests (which build on {buildCuts}). The Diamond itself is the sole
///         timelock proposer, so only the authenticated cross-chain handler can schedule operations. `Receive`
///         is part of it because the timelock holds the ETH its scheduled operations spend.
contract DeployCrosschainTimelockHandler is BaseDeploy {
    /// @notice Builds the cross-chain timelock diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (timelock + link/handler registry admin).
    /// @param minDelay The timelock's minimum operation delay.
    /// @return cuts The facet cuts (ERC165 + AccessControl + CrosschainLink + TimelockController + handler + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {CrosschainTimelockHandlerInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, uint256 minDelay)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("CrosschainTimelockHandlerInit"),
            abi.encodeCall(CrosschainTimelockHandlerInit.init, (admin, minDelay))
        );
    }

    /// @notice Deploys a cross-chain governance diamond (broadcasting entrypoint for `forge script ...`).
    /// @param admin The timelock + registry admin.
    /// @param minDelay The timelock minimum delay.
    /// @return gov The deployed cross-chain governance diamond address.
    function run(address admin, uint256 minDelay) external returns (address gov) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, minDelay);
        gov = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployCrosschainTimelockHandler: unknown variant");
        facets = new RecipeFacet[](8);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("CrosschainLink");
        facets[3] = RecipePlanLib.all("TimelockController");
        facets[4] = RecipePlanLib.all("CrosschainTimelockHandler");
        facets[5] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[6] = RecipePlanLib.all("AccessControlDiamondCut");
        facets[7] = RecipePlanLib.all("Receive");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical builder variants and exact ordered initializer calls as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec(
            "DeployCrosschainTimelockHandler", "script/base/crosschain/DeployCrosschainTimelockHandler.s.sol", 1
        );
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployCrosschainTimelockHandler:buildCuts(address,uint256)";
        variant.buildSignature = "buildCuts(address,uint256)";
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
            "minDelay",
            "uint256",
            "seconds",
            "300",
            "initialization accepts zero; caller chooses the safety delay for authenticated inbound proposals"
        );
        RecipeParameter[] memory parameters = new RecipeParameter[](2);
        parameters[0] = variant.inputs[0];
        parameters[1] = variant.inputs[1];
        string[] memory bindings = new string[](2);
        bindings[0] = "admin";
        bindings[1] = "minDelay";
        RecipeInitStep[] memory module =
            RecipeSpecLib.leaf("CrosschainTimelockHandlerInit", "init(address,uint256)", parameters, bindings);
        variant.initPlan = RecipeSpecLib.introspected(module, true);
        variant.authorities = new RecipeAuthority[](5);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "module configuration, role administration and diamondCut"
        );
        variant.authorities[1] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "address(this)",
            "TimelockController grants the diamond self-administration"
        );
        variant.authorities[2] = RecipeSpecLib.role(
            "TimelockController",
            "PROPOSER_ROLE",
            "bytes32",
            TimelockControllerLib.PROPOSER_ROLE,
            "address(this)",
            "authenticated crosschain self-dispatch schedules operations"
        );
        variant.authorities[3] = RecipeSpecLib.role(
            "TimelockController",
            "CANCELLER_ROLE",
            "bytes32",
            TimelockControllerLib.CANCELLER_ROLE,
            "address(this)",
            "the proposer also receives cancellation authority"
        );
        variant.authorities[4] = RecipeSpecLib.role(
            "TimelockController",
            "EXECUTOR_ROLE",
            "bytes32",
            TimelockControllerLib.EXECUTOR_ROLE,
            "address(0)",
            "open execution after the timelock delay"
        );
        variant.conditions = new string[](3);
        variant.conditions[0] =
            "caller: configure authenticated CrosschainLink gateways, counterparts and the timelock handler route before accepting proposals";
        variant.conditions[1] =
            "the diamond is the proposer and canceller; address(0) opens execution, while the supplied admin and diamond administer roles";
        variant.conditions[2] =
        "Receive is included so scheduled operations can spend native value; minDelay is measured in seconds";
        result.variants[0] = variant;
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployCrosschainTimelockHandler", "run(address,uint256)", variant, "buildCuts(admin,minDelay)"
        );
    }
}
