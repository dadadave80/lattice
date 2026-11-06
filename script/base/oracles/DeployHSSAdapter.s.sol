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
import {Receive as LatticeReceive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {HSSAdapter} from "@lattice/oracles/hedera/HSSAdapter.sol";
import {HSSAdapterInit} from "@lattice/oracles/hedera/HSSAdapterInit.sol";
import {HSS_SCHEDULER_ROLE} from "@lattice/oracles/hedera/HSSAdapterLib.sol";
import {HSSAdapterRecovery} from "@lattice/oracles/hedera/HSSAdapterRecovery.sol";

/// @title DeployHSSAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice HSS diamond with scheduler access, generation-bound recovery, upgrades and HBAR funding.
/// @dev Native callback sender remains unverified; this recipe's offline tests do not establish it.
contract DeployHSSAdapter is BaseDeploy {
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory data) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, data) =
            _withUpgradeableIntrospection(_init("HSSAdapterInit"), abi.encodeCall(HSSAdapterInit.init, (admin)));
    }

    function _cutPlan(uint256) internal pure returns (RecipeFacet[] memory facets) {
        facets = new RecipeFacet[](7);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("HSSAdapter");
        facets[3] = RecipePlanLib.all("HSSAdapterRecovery");
        facets[4] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[5] = RecipePlanLib.all("AccessControlDiamondCut");
        facets[6] = RecipePlanLib.all("Receive");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cuts, typed initializer bindings and deployment context as pure script data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployHSSAdapter", "script/base/oracles/DeployHSSAdapter.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployHSSAdapter:buildCuts(address)";
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
            "caller: choose a usable role administrator and upgrade authority; initialization permits the zero address"
        );
        string[] memory bindings = new string[](1);
        bindings[0] = "admin";
        variant.initPlan = RecipeSpecLib.introspected(
            RecipeSpecLib.leaf("HSSAdapterInit", "init(address)", variant.inputs, bindings), true
        );
        variant.authorities = new RecipeAuthority[](2);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "role administration and diamondCut; the scheduler role is granted separately"
        );
        variant.authorities[1] = RecipeSpecLib.role(
            "HSSAdapter",
            "HSS_SCHEDULER_ROLE",
            "bytes32",
            HSS_SCHEDULER_ROLE,
            "admin",
            "schedule, delete and authorize schedules paid by the diamond; cancel generation-bound self-calls"
        );
        variant.conditions = new string[](3);
        variant.conditions[0] =
            "enforced at initialization: executeSelfCall and cancelSelfCall are routed; caller retains the matching HSSAdapterRecovery implementation";
        variant.conditions[1] =
            "caller: Hedera HSS system contract availability and native callback sender identity remain unverified by offline recipe tests";
        variant.conditions[2] =
        "caller: fund the diamond with HBAR through Receive and do not expose an unrestricted self-call executor";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] =
            RecipeSpecLib.deploymentContext("DeployHSSAdapter", "run(address)", variant, "buildCuts(admin)");
    }

    function run(address admin) external returns (address diamond) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory data) = buildCuts(admin);
        diamond = _assemble(cuts, init, data);
        vm.stopBroadcast();
    }
}
