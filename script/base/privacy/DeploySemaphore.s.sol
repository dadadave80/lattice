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
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {Semaphore} from "@lattice/privacy/Semaphore.sol";
import {SemaphoreInit} from "@lattice/privacy/SemaphoreInit.sol";

/// @title DeploySemaphore
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Semaphore diamond: `ERC165Facet` + `AccessControl` + `Semaphore` +
///         {SemaphoreInit}. The ONE source of truth for what a Semaphore diamond is, shared by production
///         (`run --broadcast`) and the facet tests (which build on {buildCuts}). `AccessControl` is part of the
///         base recipe because `setVerifier` is `DEFAULT_ADMIN_ROLE`-gated. The off-chain proof `verifier` is an
///         external dependency address (its `ISemaphoreVerifier` mock is a test fixture, not a facet).
contract DeploySemaphore is BaseDeploy {
    /// @notice Builds the Semaphore diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls `setVerifier`).
    /// @param verifier The {ISemaphoreVerifier} contract address used to check Semaphore proofs.
    /// @return cuts The facet cuts (ERC165 + AccessControl + Semaphore + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {SemaphoreInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address verifier)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("SemaphoreInit"), abi.encodeCall(SemaphoreInit.init, (admin, verifier))
        );
    }

    /// @dev Ordered facets shared by execution and the exported recipe data.
    function _cutPlan(uint256) internal pure returns (RecipeFacet[] memory facets) {
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("Semaphore");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cuts, external initializer order and authority assignments as script data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeploySemaphore", "script/base/privacy/DeploySemaphore.s.sol", 1);
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeploySemaphore:buildCuts(address,address)";
        variant.buildSignature = "buildCuts(address,address)";
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
            "verifier",
            "address",
            "Semaphore-v4-proof-verifier",
            "mock-or-target-configured-Semaphore-verifier",
            "enforced: nonzero; initialization does not check code; caller authenticates the verifier, audited circuit and verifying key"
        );
        RecipeParameter[] memory parameters = new RecipeParameter[](2);
        parameters[0] = variant.inputs[0];
        parameters[1] = variant.inputs[1];
        string[] memory bindings = new string[](2);
        bindings[0] = "admin";
        bindings[1] = "verifier";
        RecipeInitStep[] memory module =
            RecipeSpecLib.leaf("SemaphoreInit", "init(address,address)", parameters, bindings);
        variant.initPlan = RecipeSpecLib.introspected(module, true);
        variant.authorities = new RecipeAuthority[](2);
        variant.authorities[1] = RecipeSpecLib.externalAuthority(
            "Semaphore",
            "proofVerifier",
            "verifier",
            "authenticates Semaphore membership proofs; separate from group and poll administration"
        );
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "role administration, Semaphore verifier replacement and diamondCut"
        );
        variant.conditions = new string[](2);
        variant.conditions[0] =
            "group administrators are configured through createGroup, separately from the bootstrap verifier and upgrade administrator";
        variant.conditions[1] =
            "caller: supply the matching audited Semaphore circuit, verifier and key; initialization does not establish audit status or live provider readiness";
        result.variants[0] = variant;
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeploySemaphore", "run(address,address)", variant, "buildCuts(admin,verifier)"
        );
    }

    /// @notice Deploys a Semaphore diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The Semaphore admin (controls `setVerifier`).
    /// @param verifier The {ISemaphoreVerifier} contract address.
    /// @return semaphore The deployed Semaphore diamond address.
    function run(address admin, address verifier) external returns (address semaphore) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, verifier);
        semaphore = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
