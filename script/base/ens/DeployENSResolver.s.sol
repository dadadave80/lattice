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
import {ENSResolver} from "@lattice/ens/ENSResolver.sol";
import {ENSResolverInit} from "@lattice/ens/ENSResolverInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployENSResolver
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ENS forward-resolution diamond: `ERC165Facet` + `AccessControl` +
///         `ENSResolver` + {ENSResolverInit}. The ONE source of truth for what an ENS resolver diamond is, shared
///         by production (`run --broadcast`) and the facet tests (which build on {buildCuts}). `AccessControl` is
///         part of the base recipe because the registry setter is `ENS_MANAGER_ROLE`-gated; the external ENS
///         registry the facet reads resolvers from is wired at init time.
contract DeployENSResolver is BaseDeploy {
    /// @notice Builds the ENS resolver diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls role assignment).
    /// @param registry The external ENS registry the facet reads resolvers from.
    /// @return cuts The facet cuts (ERC165 + AccessControl + ENSResolver + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {ENSResolverInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address registry)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("ENSResolverInit"), abi.encodeCall(ENSResolverInit.init, (admin, registry))
        );
    }

    /// @notice Deploys an ENS resolver diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The role admin.
    /// @param registry The external ENS registry.
    /// @return resolver The deployed ENS resolver diamond address.
    function run(address admin, address registry) external returns (address resolver) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, registry);
        resolver = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployENSResolver: unknown variant");
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("ENSResolver");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cut plan, typed initializer tree and deployment inputs as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployENSResolver", "script/base/ens/DeployENSResolver.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployENSResolver:buildCuts(address,address)";
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
            "registry",
            "address",
            "ENS-registry",
            "target-configured-ens-registry",
            "enforced: nonzero; caller authenticates the external registry and its resolver records"
        );
        string[] memory bindings = new string[](2);
        bindings[0] = "admin";
        bindings[1] = "registry";
        variant.initPlan = RecipeSpecLib.introspected(
            RecipeSpecLib.leaf("ENSResolverInit", "init(address,address)", variant.inputs, bindings), true
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
            "ENSResolver",
            "resolverRegistry",
            "registry",
            "the configured registry selects the external resolvers that supply name records"
        );
        variant.conditions = new string[](2);
        variant.conditions[0] =
            "initialization grants DEFAULT_ADMIN_ROLE only; caller must grant ENS_MANAGER_ROLE before changing the registry";
        variant.conditions[1] =
            "caller: authenticate the target network registry and the resolvers it selects before relying on resolution results";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployENSResolver", "run(address,address)", variant, "buildCuts(admin,registry)"
        );
    }
}
