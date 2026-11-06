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
import {AccessControlEnumerable} from "@lattice/access/AccessControlEnumerable.sol";
import {AccessControlEnumerableInit} from "@lattice/access/AccessControlEnumerableInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployAccessControlEnumerable
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for the enumerable role diamond: `ERC165Facet` + `AccessControlEnumerable` +
///         {AccessControlEnumerableInit}. `AccessControlEnumerable` is a drop-in AccessControl FLAVOR carrying the
///         full role surface PLUS per-role member enumeration, so it is cut in place of the base `AccessControl`
///         facet (cutting both would collide on the shared role selectors).
contract DeployAccessControlEnumerable is BaseDeploy {
    /// @notice Builds the AccessControlEnumerable diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return cuts The facet cuts (ERC165 + AccessControlEnumerable + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {AccessControlEnumerableInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("AccessControlEnumerableInit"), abi.encodeCall(AccessControlEnumerableInit.init, (admin))
        );
    }

    /// @dev The ordered facets shared by the builder and its exported recipe data.
    function _cutPlan(uint256) internal pure returns (RecipeFacet[] memory facets) {
        facets = new RecipeFacet[](4);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControlEnumerable");
        facets[2] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[3] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cuts, typed initializer order and assigned authorities as script data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec(
            "DeployAccessControlEnumerable", "script/base/access/DeployAccessControlEnumerable.s.sol", 1
        );
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployAccessControlEnumerable:buildCuts(address)";
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
            "caller: choose a usable role administrator; initialization permits the zero address"
        );
        RecipeParameter[] memory parameters = new RecipeParameter[](1);
        parameters[0] = variant.inputs[0];
        string[] memory bindings = new string[](1);
        bindings[0] = "admin";
        RecipeInitStep[] memory module =
            RecipeSpecLib.leaf("AccessControlEnumerableInit", "init(address)", parameters, bindings);
        variant.initPlan = RecipeSpecLib.introspected(module, true);
        variant.authorities = new RecipeAuthority[](1);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "role administration, module management and diamondCut"
        );
        variant.conditions = new string[](0);
        result.variants[0] = variant;
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployAccessControlEnumerable", "run(address)", variant, "buildCuts(admin)"
        );
    }

    /// @notice Deploys an AccessControlEnumerable diamond (broadcasting entrypoint for `forge script`).
    /// @param admin The role admin.
    /// @return accessControl The deployed AccessControlEnumerable diamond address.
    function run(address admin) external returns (address accessControl) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        accessControl = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
