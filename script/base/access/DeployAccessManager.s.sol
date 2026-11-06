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
import {AccessManager} from "@lattice/access/AccessManager.sol";
import {AccessManagerInit} from "@lattice/access/AccessManagerInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployAccessManager
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an AccessManager authority diamond: `ERC165Facet` + `AccessManager` +
///         {AccessManagerInit}. The AccessManager self-gates its admin surface on its own `ADMIN_ROLE` (no
///         AccessControl facet needed); `admin` receives that initial role. This diamond is both a standalone
///         authority and the authority backing {DeployAccessManaged}. Keep it a separate diamond: cut next to
///         other modules, `admin`'s ADMIN_ROLE is root over them, because `execute(address(this), ...)` reaches
///         every facet as the diamond itself (issue #240). The ADMIN overload is safe only because the diamond
///         holds no AccessControl role, so that path cannot reach `AccessControlDiamondCut`.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut; deploy a new diamond to change
///      behavior. Use the ADMIN overload (`buildCuts(..., admin)` / `run(..., admin)`) for an upgradeable
///      deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployAccessManager is BaseDeploy {
    /// @notice Builds the AccessManager diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted the initial `ADMIN_ROLE`.
    /// @return cuts The facet cuts (ERC165 + AccessManager).
    /// @return init The {MultiInit} running {AccessManagerInit} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) =
            _withImmutableIntrospection(_init("AccessManagerInit"), abi.encodeCall(AccessManagerInit.init, (admin)));
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `upgradeAdmin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(address admin, address upgradeAdmin)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(1), _recipeSeams(1));
        (init, initCalldata) = _withAdminUpgradeableIntrospection(
            _init("AccessManagerInit"), abi.encodeCall(AccessManagerInit.init, (admin)), upgradeAdmin
        );
    }

    /// @dev The ordered facets shared by the builder and its exported recipe data.
    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant < 2, "DeployAccessManager: unknown variant");
        facets = new RecipeFacet[](variant == 0 ? 3 : 5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessManager");
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
        result = RecipeSpecLib.spec("DeployAccessManager", "script/base/access/DeployAccessManager.s.sol", 2);
        result.deploymentContexts = new RecipeDeploymentContext[](2);
        for (uint256 i; i < 2; ++i) {
            RecipeVariant memory variant;
            variant.id =
                i == 0 ? "DeployAccessManager:buildCuts(address)" : "DeployAccessManager:buildCuts(address,address)";
            variant.buildSignature = i == 0 ? "buildCuts(address)" : "buildCuts(address,address)";
            variant.proxyKind = RecipeProxyKind.Lattice;
            variant.initOutputKind = RecipeInitOutputKind.Single;
            variant.facets = _cutPlan(i);
            variant.seams = _recipeSeams(i);
            variant.inputs = new RecipeParameter[](i == 0 ? 1 : 2);
            variant.inputs[0] = RecipeParameter(
                "admin",
                "address",
                "account",
                "0x00000000000000000000000000000000000000ad",
                "enforced: nonzero initial AccessManager admin"
            );
            RecipeParameter[] memory parameters = new RecipeParameter[](1);
            parameters[0] = variant.inputs[0];
            string[] memory bindings = new string[](1);
            bindings[0] = "admin";
            RecipeInitStep[] memory module =
                RecipeSpecLib.leaf("AccessManagerInit", "init(address)", parameters, bindings);
            if (i == 0) {
                variant.initPlan = RecipeSpecLib.introspected(module, false);
            } else {
                variant.inputs[1] = RecipeParameter(
                    "upgradeAdmin",
                    "address",
                    "account",
                    "0x00000000000000000000000000000000000000ad",
                    "caller: choose a usable role administrator; initialization permits the zero address"
                );
                variant.initPlan = RecipeSpecLib.adminIntrospected(module, "upgradeAdmin");
            }
            variant.authorities = new RecipeAuthority[](i == 0 ? 1 : 2);
            variant.authorities[0] = RecipeSpecLib.role(
                "AccessManager",
                "ADMIN_ROLE",
                "uint64",
                bytes32(0),
                "admin",
                "AccessManager administration and execution with initial execution delay zero; distinct from the cut role"
            );
            if (i == 1) {
                variant.authorities[1] = RecipeSpecLib.role(
                    "AccessControl",
                    "DEFAULT_ADMIN_ROLE",
                    "bytes32",
                    bytes32(0),
                    "upgradeAdmin",
                    "role administration and diamondCut"
                );
            }
            variant.conditions = new string[](2);
            variant.conditions[0] =
                "Keep this authority on a separate diamond: execute(address(this),...) reaches co-cut facets as diamond-self";
            variant.conditions[1] =
                "caller: do not grant diamond-self an AccessControl role; ADMIN_ROLE and the optional upgradeAdmin are independent";
            result.variants[i] = variant;
            result.deploymentContexts[i] = RecipeSpecLib.deploymentContext(
                "DeployAccessManager",
                i == 0 ? "run(address)" : "run(address,address)",
                variant,
                i == 0 ? "buildCuts(admin)" : "buildCuts(admin,upgradeAdmin)"
            );
        }
    }

    /// @notice Deploys an AccessManager authority diamond (broadcasting entrypoint for `forge script`).
    /// @param admin The initial admin.
    /// @return manager The deployed AccessManager diamond address.
    function run(address admin) external returns (address manager) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        manager = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `upgradeAdmin` can `diamondCut`.
    function run(address admin, address upgradeAdmin) external returns (address manager) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, upgradeAdmin);
        manager = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
