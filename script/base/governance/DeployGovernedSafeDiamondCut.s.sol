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
import {GovernedSafeDiamondCut} from "@lattice/governance/GovernedSafeDiamondCut.sol";
import {GovernedSafeDiamondCutInit} from "@lattice/governance/GovernedSafeDiamondCutInit.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";

/// @title DeployGovernedSafeDiamondCut
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Safe-gated, timelocked diamond-cut diamond: `ERC165Facet` +
///         `DiamondLoupeFacet` + `AccessControl` + `EmergencyStop` + `GovernedSafeDiamondCut` +
///         {GovernedSafeDiamondCutInit}. The ONE source of truth for what a governed-Safe-cut diamond is,
///         shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}). Unlike
///         {SafeDiamondCut} the facet deliberately does NOT serve the synchronous cut selector `0x1f931c1c`
///         (every cut is scheduled, matures past `minDelay`, then executed by the pinned Safe);
///         `AccessControl` + `EmergencyStop` are part of the base recipe because the emergency + guardian
///         surface is role-gated, and `DiamondLoupeFacet` exposes `facetAddress` so tests can verify an
///         applied cut.
contract DeployGovernedSafeDiamondCut is BaseDeploy {
    /// @notice Builds the governed-Safe-cut diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (manages guardians and resumes operation).
    /// @param safe The Gnosis Safe multisig pinned as the sole scheduling/execution authority.
    /// @param minThreshold The minimum signature threshold the pinned Safe must enforce.
    /// @param minDelay The minimum timelock delay (seconds) between schedule and execute.
    /// @return cuts The facet cuts (ERC165 + Loupe + AccessControl + EmergencyStop + GovernedSafeDiamondCut).
    /// @return init The {GovernedSafeDiamondCutInit} initializer address.
    /// @return initCalldata The `init(admin, safe, minThreshold, minDelay)` calldata.
    function buildCuts(address admin, address safe, uint256 minThreshold, uint256 minDelay)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        init = _init("GovernedSafeDiamondCutInit");
        initCalldata = abi.encodeCall(GovernedSafeDiamondCutInit.init, (admin, safe, minThreshold, minDelay));
    }

    function _cutPlan(uint256) internal pure returns (RecipeFacet[] memory facets) {
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[2] = RecipePlanLib.all("AccessControl");
        facets[3] = RecipePlanLib.all("EmergencyStop");
        facets[4] = RecipePlanLib.all("GovernedSafeDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Exact cut topology, initializer and assigned authority; no full voting system is implied.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec(
            "DeployGovernedSafeDiamondCut", "script/base/governance/DeployGovernedSafeDiamondCut.s.sol", 1
        );
        RecipeVariant memory variant;
        variant.id = "DeployGovernedSafeDiamondCut:buildCuts(address,address,uint256,uint256)";
        variant.buildSignature = "buildCuts(address,address,uint256,uint256)";
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
            "caller: choose a usable guardian/role administrator; AccessControl initialization permits the zero address"
        );
        variant.inputs[1] = RecipeParameter(
            "safe",
            "address",
            "Safe-compatible-authority",
            "target-configured-safe",
            "enforced at initialization: nonzero and getThreshold() at least minThreshold; caller authenticates the Safe implementation"
        );
        variant.inputs[2] = RecipeParameter(
            "minThreshold",
            "uint256",
            "signature-count",
            "1",
            "enforced at initialization: greater than zero and no larger than the Safe threshold; this is an admission check, not a stored ongoing threshold policy"
        );
        variant.inputs[3] = RecipeParameter(
            "minDelay",
            "uint256",
            "seconds",
            "300",
            "initialization accepts zero; caller chooses an operational delay and zero provides no waiting period"
        );
        string[] memory bindings = new string[](4);
        bindings[0] = "admin";
        bindings[1] = "safe";
        bindings[2] = "minThreshold";
        bindings[3] = "minDelay";
        variant.initPlan = RecipeSpecLib.leaf(
            "GovernedSafeDiamondCutInit", "init(address,address,uint256,uint256)", variant.inputs, bindings
        );
        variant.authorities = new RecipeAuthority[](2);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "guardian management, emergency resume and role administration; this role alone does not authorize ordinary cuts"
        );
        variant.authorities[1] = RecipeSpecLib.externalAuthority(
            "GovernedSafeDiamondCut",
            "scheduleExecuteAuthority",
            "safe",
            "the pinned Safe alone schedules and executes matured cuts, rotates the Safe and requests delay changes"
        );
        variant.conditions = new string[](5);
        variant.conditions[0] =
            "the cut surface is asynchronous scheduleCut/executeCut; the synchronous diamondCut selector 0x1f931c1c is neither routed nor advertised";
        variant.conditions[1] =
            "only the pinned Safe schedules and executes cuts; the AccessControl admin manages the separate guardian and stop-recovery surface";
        variant.conditions[2] =
            "minThreshold is checked at initialization; the Safe controls its own signing policy and rotation validates a replacement with minimum threshold one";
        variant.conditions[3] =
        "minDelay is measured in seconds and may be zero; later changes use the pending-delay policy";
        variant.conditions[4] =
            "the initializer grants no guardian role and freezes no selector; no Governor or TimelockController facet is cut or voting state initialized";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployGovernedSafeDiamondCut",
            "run(address,address,uint256,uint256)",
            variant,
            "buildCuts(admin,safe,minThreshold,minDelay)"
        );
    }

    /// @notice Deploys a governed-Safe-cut diamond (broadcasting entrypoint for `forge script ...
    ///         --broadcast`).
    /// @param admin The governance admin.
    /// @param safe The pinned Safe authority.
    /// @param minThreshold The minimum Safe signature threshold.
    /// @param minDelay The minimum timelock delay (seconds).
    /// @return governedSafeDiamond The deployed governed-Safe-cut diamond address.
    function run(address admin, address safe, uint256 minThreshold, uint256 minDelay)
        external
        returns (address governedSafeDiamond)
    {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            buildCuts(admin, safe, minThreshold, minDelay);
        governedSafeDiamond = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
