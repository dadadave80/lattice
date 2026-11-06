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
import {AccessManaged} from "@lattice/access/AccessManaged.sol";
import {AccessManagedInit} from "@lattice/access/AccessManagedInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployAccessManaged
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a managed diamond: `ERC165Facet` + `AccessManaged` + {AccessManagedInit}.
///         `AccessManaged` defers every authorization decision to an external AccessManager `authority` (deploy
///         one with {DeployAccessManager}); the init pins that authority. The ONE source of truth for what a
///         managed diamond is, shared by production (`run --broadcast`) and the facet tests.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut; deploy a new diamond to change
///      behavior. Use the ADMIN overload (`buildCuts(..., admin)` / `run(..., admin)`) for an upgradeable
///      deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployAccessManaged is BaseDeploy {
    /// @notice Builds the AccessManaged diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param authority The AccessManager authority governing this contract.
    /// @return cuts The facet cuts (ERC165 + AccessManaged).
    /// @return init The {MultiInit} running {AccessManagedInit} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address authority)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withImmutableIntrospection(
            _init("AccessManagedInit"), abi.encodeCall(AccessManagedInit.init, (authority))
        );
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(address authority, address admin)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(1), _recipeSeams(1));
        (init, initCalldata) = _withAdminUpgradeableIntrospection(
            _init("AccessManagedInit"), abi.encodeCall(AccessManagedInit.init, (authority)), admin
        );
    }

    /// @dev The ordered facets shared by the builder and its exported recipe data.
    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant < 2, "DeployAccessManaged: unknown variant");
        facets = new RecipeFacet[](variant == 0 ? 3 : 5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessManaged");
        facets[2] = RecipePlanLib.all("DiamondLoupeFacet");
        if (variant == 1) {
            facets[3] = RecipePlanLib.all("AccessControl");
            facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
        }
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cuts, typed initializer order and assigned authorities as script data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployAccessManaged", "script/base/access/DeployAccessManaged.s.sol", 2);
        result.deploymentContexts = new RecipeDeploymentContext[](2);
        for (uint256 i; i < 2; ++i) {
            RecipeVariant memory variant;
            variant.id =
                i == 0 ? "DeployAccessManaged:buildCuts(address)" : "DeployAccessManaged:buildCuts(address,address)";
            variant.buildSignature = i == 0 ? "buildCuts(address)" : "buildCuts(address,address)";
            variant.proxyKind = RecipeProxyKind.Lattice;
            variant.initOutputKind = RecipeInitOutputKind.Single;
            variant.facets = _cutPlan(i);
            variant.seams = _recipeSeams(i);
            variant.inputs = new RecipeParameter[](i == 0 ? 1 : 2);
            variant.inputs[0] = RecipeParameter(
                "authority",
                "address",
                "external-authority",
                "target-configured-authority",
                "enforced: nonzero contract; caller authenticates the external authority implementation"
            );
            RecipeParameter[] memory parameters = new RecipeParameter[](1);
            parameters[0] = variant.inputs[0];
            string[] memory bindings = new string[](1);
            bindings[0] = "authority";
            RecipeInitStep[] memory module =
                RecipeSpecLib.leaf("AccessManagedInit", "init(address)", parameters, bindings);
            if (i == 0) {
                variant.initPlan = RecipeSpecLib.introspected(module, false);
            } else {
                variant.inputs[1] = RecipeParameter(
                    "admin",
                    "address",
                    "account",
                    "0x00000000000000000000000000000000000000ad",
                    "caller: choose a usable role administrator; initialization permits the zero address"
                );
                variant.initPlan = RecipeSpecLib.adminIntrospected(module, "admin");
            }
            variant.authorities = new RecipeAuthority[](i == 0 ? 1 : 2);
            variant.authorities[0] = RecipeSpecLib.externalAuthority(
                "AccessManaged",
                "authority",
                "authority",
                "managed authorization and authority replacement; independent of the optional cut administrator"
            );
            if (i == 1) {
                variant.authorities[1] = RecipeSpecLib.role(
                    "AccessControl",
                    "DEFAULT_ADMIN_ROLE",
                    "bytes32",
                    bytes32(0),
                    "admin",
                    "role administration and diamondCut"
                );
            }
            variant.conditions = new string[](0);
            result.variants[i] = variant;
            result.deploymentContexts[i] = RecipeSpecLib.deploymentContext(
                "DeployAccessManaged",
                i == 0 ? "run(address)" : "run(address,address)",
                variant,
                i == 0 ? "buildCuts(authority)" : "buildCuts(authority,admin)"
            );
        }
    }

    /// @notice Deploys a managed diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param authority The AccessManager authority.
    /// @return managed The deployed managed diamond address.
    function run(address authority) external returns (address managed) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(authority);
        managed = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(address authority, address admin) external returns (address managed) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(authority, admin);
        managed = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
