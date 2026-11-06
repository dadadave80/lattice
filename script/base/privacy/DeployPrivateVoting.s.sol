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
import {PrivateVoting} from "@lattice/privacy/PrivateVoting.sol";
import {PrivateVotingInit} from "@lattice/privacy/PrivateVotingInit.sol";
import {Semaphore} from "@lattice/privacy/Semaphore.sol";

/// @title DeployPrivateVoting
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an anonymous-voting diamond: `ERC165Facet` + `Semaphore` + `PrivateVoting`
///         + {PrivateVotingInit}. The ONE source of truth for what a private-voting diamond is, shared by
///         production (`run --broadcast`) and the facet tests (which build on {buildCuts}). PrivateVoting layers
///         1p1v tallying on top of the `Semaphore` membership facet, so BOTH facets are cut in. Poll and group
///         admin are per-group (set by `createGroup`), so there is NO `AccessControl` in the recipe. The off-chain
///         proof `verifier` is an external dependency address (its `ISemaphoreVerifier` mock is a test fixture).
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut; deploy a new diamond to change
///      behavior. Use the ADMIN overload (`buildCuts(..., admin)` / `run(..., admin)`) for an upgradeable
///      deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployPrivateVoting is BaseDeploy {
    /// @notice Builds the PrivateVoting diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param verifier The {ISemaphoreVerifier} contract address used to check the anonymous vote proofs.
    /// @return cuts The facet cuts (ERC165 + Semaphore + PrivateVoting).
    /// @return init The {MultiInit} running {PrivateVotingInit} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address verifier)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) =
            _withImmutableIntrospection(_init("PrivateVotingInit"), abi.encodeCall(PrivateVotingInit.init, (verifier)));
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(address verifier, address admin)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(1), _recipeSeams(1));
        (init, initCalldata) = _withAdminUpgradeableIntrospection(
            _init("PrivateVotingInit"), abi.encodeCall(PrivateVotingInit.init, (verifier)), admin
        );
    }

    /// @dev Ordered facets shared by execution and the exported recipe data.
    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant < 2, "DeployPrivateVoting: unknown variant");
        facets = new RecipeFacet[](variant == 0 ? 4 : 6);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("Semaphore");
        facets[2] = RecipePlanLib.all("PrivateVoting");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        if (variant == 1) {
            facets[4] = RecipePlanLib.all("AccessControl");
            facets[5] = RecipePlanLib.all("AccessControlDiamondCut");
        }
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cuts, external initializer order and authority assignments as script data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployPrivateVoting", "script/base/privacy/DeployPrivateVoting.s.sol", 2);
        result.deploymentContexts = new RecipeDeploymentContext[](2);
        for (uint256 i; i < 2; ++i) {
            RecipeVariant memory variant;
            variant.id =
                i == 0 ? "DeployPrivateVoting:buildCuts(address)" : "DeployPrivateVoting:buildCuts(address,address)";
            variant.buildSignature = i == 0 ? "buildCuts(address)" : "buildCuts(address,address)";
            variant.proxyKind = RecipeProxyKind.Lattice;
            variant.initOutputKind = RecipeInitOutputKind.Single;
            variant.facets = _cutPlan(i);
            variant.seams = _recipeSeams(i);
            variant.inputs = new RecipeParameter[](i == 0 ? 1 : 2);
            variant.inputs[0] = RecipeParameter(
                "verifier",
                "address",
                "Semaphore-v4-proof-verifier",
                "mock-or-target-configured-Semaphore-verifier",
                "enforced: nonzero; initialization does not check code; caller authenticates the verifier, audited circuit and verifying key"
            );
            RecipeParameter[] memory parameters = new RecipeParameter[](1);
            parameters[0] = variant.inputs[0];
            string[] memory bindings = new string[](1);
            bindings[0] = "verifier";
            RecipeInitStep[] memory module =
                RecipeSpecLib.leaf("PrivateVotingInit", "init(address)", parameters, bindings);
            if (i == 0) {
                variant.initPlan = RecipeSpecLib.introspected(module, false);
            } else {
                variant.inputs[1] = RecipeParameter(
                    "admin",
                    "address",
                    "account",
                    "0x00000000000000000000000000000000000000ad",
                    "caller: choose a usable role and upgrade administrator; initialization permits the zero address"
                );
                variant.initPlan = RecipeSpecLib.adminIntrospected(module, "admin");
            }
            variant.authorities = new RecipeAuthority[](i == 0 ? 1 : 2);
            variant.authorities[0] = RecipeSpecLib.externalAuthority(
                "Semaphore",
                "proofVerifier",
                "verifier",
                "authenticates Semaphore membership proofs; separate from group and poll administration"
            );
            if (i == 1) {
                variant.authorities[1] = RecipeSpecLib.role(
                    "AccessControl",
                    "DEFAULT_ADMIN_ROLE",
                    "bytes32",
                    bytes32(0),
                    "admin",
                    "role administration, Semaphore verifier replacement and diamondCut"
                );
            }
            variant.conditions = new string[](3);
            variant.conditions[0] =
                "group and poll administration is configured through createGroup, independently of the optional AccessControl upgrade administrator";
            variant.conditions[1] =
            "anonymous voting is one-person-one-vote; token-weighted private voting remains deferred under ADR0010";
            variant.conditions[2] =
                "caller: supply the matching audited Semaphore circuit, verifier and key; test fixture verifiers are not production circuit evidence";
            result.variants[i] = variant;
            result.deploymentContexts[i] = RecipeSpecLib.deploymentContext(
                "DeployPrivateVoting",
                i == 0 ? "run(address)" : "run(address,address)",
                variant,
                i == 0 ? "buildCuts(verifier)" : "buildCuts(verifier,admin)"
            );
        }
    }

    /// @notice Deploys a PrivateVoting diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param verifier The {ISemaphoreVerifier} contract address.
    /// @return voting The deployed private-voting diamond address.
    function run(address verifier) external returns (address voting) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(verifier);
        voting = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(address verifier, address admin) external returns (address voting) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(verifier, admin);
        voting = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
