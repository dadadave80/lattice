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
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {SafeHarborAdopter} from "@lattice/governance/SafeHarborAdopter.sol";
import {SafeHarborAdopterInit} from "@lattice/governance/SafeHarborAdopterInit.sol";

/// @title DeploySafeHarborAdopter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a SafeHarborAdopter diamond: `ERC165Facet` + `AccessControl` +
///         `SafeHarborAdopter` + {SafeHarborAdopterInit}. The ONE source of truth for what a Safe Harbor
///         adopter diamond is, shared by production (`run --broadcast`) and the facet tests (which build on
///         {buildCuts}). `AccessControl` is part of the base recipe because every adoption/configuration
///         setter is `SAFE_HARBOR_ADMIN_ROLE`-gated (that role is administered by `DEFAULT_ADMIN_ROLE`).
contract DeploySafeHarborAdopter is BaseDeploy {
    /// @notice Builds the SafeHarborAdopter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (administers `SAFE_HARBOR_ADMIN_ROLE`).
    /// @param registry The SEAL SafeHarborRegistry for this chain (must be non-zero).
    /// @param factory The SEAL AgreementFactory for this chain (zero allowed; disables `createAndAdopt`).
    /// @return cuts The facet cuts (ERC165 + AccessControl + SafeHarborAdopter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {SafeHarborAdopterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address registry, address factory)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("SafeHarborAdopterInit"), abi.encodeCall(SafeHarborAdopterInit.init, (admin, registry, factory))
        );
    }

    /// @notice Deploys a SafeHarborAdopter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The Safe Harbor admin (root `DEFAULT_ADMIN_ROLE`).
    /// @param registry The SEAL SafeHarborRegistry for this chain.
    /// @param factory The SEAL AgreementFactory for this chain (zero allowed).
    /// @return adopter The deployed Safe Harbor adopter diamond address.
    function run(address admin, address registry, address factory) external returns (address adopter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, registry, factory);
        adopter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeploySafeHarborAdopter: unknown variant");
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("SafeHarborAdopter");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cut plan, typed initializer tree and deployment inputs as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result =
            RecipeSpecLib.spec("DeploySafeHarborAdopter", "script/base/governance/DeploySafeHarborAdopter.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeploySafeHarborAdopter:buildCuts(address,address,address)";
        variant.buildSignature = "buildCuts(address,address,address)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Single;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](3);
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
            "SEAL-SafeHarborRegistry",
            "target-configured-safe-harbor-registry",
            "enforced: nonzero; caller authenticates the SEAL registry for the target chain"
        );
        variant.inputs[2] = RecipeParameter(
            "factory",
            "address",
            "SEAL-AgreementFactory-or-disabled",
            "0x0000000000000000000000000000000000000000",
            "zero is allowed and disables createAndAdopt; caller authenticates any configured nonzero agreement factory"
        );
        string[] memory bindings = new string[](3);
        bindings[0] = "admin";
        bindings[1] = "registry";
        bindings[2] = "factory";
        variant.initPlan = RecipeSpecLib.introspected(
            RecipeSpecLib.leaf("SafeHarborAdopterInit", "init(address,address,address)", variant.inputs, bindings), true
        );
        variant.authorities = new RecipeAuthority[](3);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "role administration and diamondCut; SAFE_HARBOR_ADMIN_ROLE requires a separate grant"
        );
        variant.authorities[1] = RecipeSpecLib.externalAuthority(
            "SafeHarborAdopter",
            "adoptionRegistry",
            "registry",
            "the configured external registry records the diamond agreement adoption"
        );
        variant.authorities[2] = RecipeSpecLib.externalAuthority(
            "SafeHarborAdopter",
            "optionalAgreementFactory",
            "factory",
            "when nonzero creates agreements for createAndAdopt; zero disables that operation"
        );
        variant.conditions = new string[](3);
        variant.conditions[0] =
            "initialization grants DEFAULT_ADMIN_ROLE only; caller must grant SAFE_HARBOR_ADMIN_ROLE before adoption or configuration";
        variant.conditions[1] =
            "factory=address(0) disables createAndAdopt; adopting an existing agreement still uses the configured registry";
        variant.conditions[2] =
            "caller: verify the registry and any nonzero agreement factory are authentic deployments for the target chain";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeploySafeHarborAdopter", "run(address,address,address)", variant, "buildCuts(admin,registry,factory)"
        );
    }
}
