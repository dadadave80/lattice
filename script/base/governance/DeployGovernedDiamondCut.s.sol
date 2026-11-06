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
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {GovernedDiamondCut} from "@lattice/governance/GovernedDiamondCut.sol";
import {GovernedDiamondCutInit} from "@lattice/governance/GovernedDiamondCutInit.sol";
import {UPGRADE_EXECUTOR_ROLE} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";

/// @title DeployGovernedDiamondCut
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a governed diamond-cut diamond: `ERC165Facet` + `DiamondLoupeFacet` +
///         `AccessControl` + `EmergencyStop` + `GovernedDiamondCut` + {GovernedDiamondCutInit}. The ONE
///         source of truth for what a governed-cut diamond is, shared by production (`run --broadcast`) and
///         the facet tests (which build on {buildCuts}). The cut facet OWNS the canonical `diamondCut`
///         selector `0x1f931c1c`, gated by EmergencyStop + `UPGRADE_EXECUTOR_ROLE`; `AccessControl` +
///         `EmergencyStop` are part of the base recipe because the emergency + guardian surface is
///         role-gated, and `DiamondLoupeFacet` exposes `facetAddress` so tests can verify an applied cut.
contract DeployGovernedDiamondCut is BaseDeploy {
    /// @notice Builds the governed-cut diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (manages guardians and resumes operation).
    /// @return cuts The facet cuts (ERC165 + Loupe + AccessControl + EmergencyStop + GovernedDiamondCut).
    /// @return init The {GovernedDiamondCutInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        init = _init("GovernedDiamondCutInit");
        initCalldata = abi.encodeCall(GovernedDiamondCutInit.init, (admin));
    }

    function _cutPlan(uint256) internal pure returns (RecipeFacet[] memory facets) {
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[2] = RecipePlanLib.all("AccessControl");
        facets[3] = RecipePlanLib.all("EmergencyStop");
        facets[4] = RecipePlanLib.all("GovernedDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Exact cut topology, initializer and assigned authority; no full voting system is implied.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result =
            RecipeSpecLib.spec("DeployGovernedDiamondCut", "script/base/governance/DeployGovernedDiamondCut.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployGovernedDiamondCut:buildCuts(address)";
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
            "caller: choose a usable guardian/role administrator; AccessControl initialization permits the zero address"
        );
        string[] memory bindings = new string[](1);
        bindings[0] = "admin";
        variant.initPlan = RecipeSpecLib.leaf("GovernedDiamondCutInit", "init(address)", variant.inputs, bindings);
        variant.authorities = new RecipeAuthority[](2);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "guardian management, emergency resume and role administration; this role alone does not authorize ordinary cuts"
        );
        variant.authorities[1] = RecipeSpecLib.role(
            "GovernedDiamondCut",
            "UPGRADE_EXECUTOR_ROLE",
            "bytes32",
            UPGRADE_EXECUTOR_ROLE,
            "address(this)",
            "the bundle grants the diamond its cut-executor role and makes that role self-administered"
        );
        variant.conditions = new string[](5);
        variant.conditions[0] =
            "the bundle declares Governor with policy=governed-cut-route only; it does not initialize full Governor voting state, a vote token or a timelock";
        variant.conditions[1] =
            "enforced: the synchronous cut route has an installed nonzero owner; caller pairs this trusted policy declaration with the matching GovernedDiamondCut implementation";
        variant.conditions[2] = "UPGRADE_EXECUTOR_ROLE administers itself; DEFAULT_ADMIN_ROLE cannot grant or revoke it";
        variant.conditions[3] =
            "caller: compose a reviewed reachable self-execution path; this standalone cut recipe supplies no Governor/Timelock path and must not be paired with an unrestricted external self-call relay";
        variant.conditions[4] =
            "the initializer grants no guardian role and freezes no selector; the admin manages guardians and emergency resume separately";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] =
            RecipeSpecLib.deploymentContext("DeployGovernedDiamondCut", "run(address)", variant, "buildCuts(admin)");
    }

    /// @notice Deploys a governed-cut diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The governance admin.
    /// @return governedDiamond The deployed governed-cut diamond address.
    function run(address admin) external returns (address governedDiamond) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        governedDiamond = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
