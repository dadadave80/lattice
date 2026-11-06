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
import {ENSReverseClaimer} from "@lattice/ens/ENSReverseClaimer.sol";
import {ENSReverseClaimerInit} from "@lattice/ens/ENSReverseClaimerInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployENSReverseClaimer
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ENS reverse-claim diamond: `ERC165Facet` + `AccessControl` +
///         `ENSReverseClaimer` + {ENSReverseClaimerInit}. The ONE source of truth for what an ENS reverse-claimer
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because `setEnsName` and the registrar setter are
///         `ENS_MANAGER_ROLE`-gated; the external ENS reverse registrar is wired at init time.
contract DeployENSReverseClaimer is BaseDeploy {
    /// @notice Builds the ENS reverse-claimer diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls role assignment).
    /// @param registrar The external ENS reverse registrar the facet forwards `setName` to.
    /// @return cuts The facet cuts (ERC165 + AccessControl + ENSReverseClaimer + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {ENSReverseClaimerInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address registrar)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("ENSReverseClaimerInit"), abi.encodeCall(ENSReverseClaimerInit.init, (admin, registrar))
        );
    }

    /// @notice Deploys an ENS reverse-claimer diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The role admin.
    /// @param registrar The external ENS reverse registrar.
    /// @return claimer The deployed ENS reverse-claimer diamond address.
    function run(address admin, address registrar) external returns (address claimer) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, registrar);
        claimer = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployENSReverseClaimer: unknown variant");
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("ENSReverseClaimer");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cut plan, typed initializer tree and deployment inputs as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployENSReverseClaimer", "script/base/ens/DeployENSReverseClaimer.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployENSReverseClaimer:buildCuts(address,address)";
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
            "registrar",
            "address",
            "ENS-reverse-registrar",
            "target-configured-reverse-registrar",
            "enforced: nonzero; caller authenticates the reverse registrar for the target network"
        );
        string[] memory bindings = new string[](2);
        bindings[0] = "admin";
        bindings[1] = "registrar";
        variant.initPlan = RecipeSpecLib.introspected(
            RecipeSpecLib.leaf("ENSReverseClaimerInit", "init(address,address)", variant.inputs, bindings), true
        );
        variant.authorities = new RecipeAuthority[](2);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "role administration and diamondCut; ENS_MANAGER_ROLE requires a separate grant"
        );
        variant.authorities[1] = RecipeSpecLib.externalAuthority(
            "ENSReverseClaimer",
            "reverseRegistrar",
            "registrar",
            "the configured external registrar records reverse names for this diamond"
        );
        variant.conditions = new string[](2);
        variant.conditions[0] =
            "initialization grants DEFAULT_ADMIN_ROLE only; caller must grant ENS_MANAGER_ROLE before setEnsName or registrar changes";
        variant.conditions[1] = "reverse-name calls execute as this diamond against the configured external registrar";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployENSReverseClaimer", "run(address,address)", variant, "buildCuts(admin,registrar)"
        );
    }
}
