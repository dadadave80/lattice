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
import {ERC5564Announcer} from "@lattice/privacy/ERC5564Announcer.sol";
import {ERC5564AnnouncerInit} from "@lattice/privacy/ERC5564AnnouncerInit.sol";

/// @title DeployERC5564Announcer
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-5564 stealth-address announcer diamond: `ERC165Facet` +
///         `ERC5564Announcer` + {ERC5564AnnouncerInit}. The ONE source of truth for what an announcer diamond is,
///         shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}). No
///         AccessControl is cut because `announce` is permissionless (any caller may emit an announcement).
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut; deploy a new diamond to change
///      behavior. Use the ADMIN overload (`buildCuts(..., admin)` / `run(..., admin)`) for an upgradeable
///      deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployERC5564Announcer is BaseDeploy {
    /// @notice Builds the ERC-5564 announcer diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @return cuts The facet cuts (ERC165 + ERC5564Announcer).
    /// @return init The {MultiInit} running {ERC5564AnnouncerInit} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts() public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) =
            _withImmutableIntrospection(_init("ERC5564AnnouncerInit"), abi.encodeCall(ERC5564AnnouncerInit.init, ()));
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(1), _recipeSeams(1));
        (init, initCalldata) = _withAdminUpgradeableIntrospection(
            _init("ERC5564AnnouncerInit"), abi.encodeCall(ERC5564AnnouncerInit.init, ()), admin
        );
    }

    /// @dev Ordered facets shared by execution and the exported recipe data.
    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant < 2, "DeployERC5564Announcer: unknown variant");
        facets = new RecipeFacet[](variant == 0 ? 3 : 5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("ERC5564Announcer");
        facets[2] = RecipePlanLib.all("DiamondLoupeFacet");
        if (variant == 1) {
            facets[3] = RecipePlanLib.all("AccessControl");
            facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
        }
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cuts, external initializer order and authority assignments as script data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC5564Announcer", "script/base/privacy/DeployERC5564Announcer.s.sol", 2);
        result.deploymentContexts = new RecipeDeploymentContext[](2);
        for (uint256 i; i < 2; ++i) {
            RecipeVariant memory variant;
            variant.id = i == 0 ? "DeployERC5564Announcer:buildCuts()" : "DeployERC5564Announcer:buildCuts(address)";
            variant.buildSignature = i == 0 ? "buildCuts()" : "buildCuts(address)";
            variant.proxyKind = RecipeProxyKind.Lattice;
            variant.initOutputKind = RecipeInitOutputKind.Single;
            variant.facets = _cutPlan(i);
            variant.seams = _recipeSeams(i);
            variant.inputs = new RecipeParameter[](i == 0 ? 0 : 1);
            RecipeInitStep[] memory module = RecipeSpecLib.emptyLeaf("ERC5564AnnouncerInit", "init()");
            if (i == 0) {
                variant.initPlan = RecipeSpecLib.introspected(module, false);
            } else {
                variant.inputs[0] = RecipeParameter(
                    "admin",
                    "address",
                    "account",
                    "0x00000000000000000000000000000000000000ad",
                    "caller: choose a usable role and upgrade administrator; initialization permits the zero address"
                );
                variant.initPlan = RecipeSpecLib.adminIntrospected(module, "admin");
            }
            variant.authorities = new RecipeAuthority[](i == 0 ? 0 : 1);
            if (i == 1) {
                variant.authorities[0] = RecipeSpecLib.role(
                    "AccessControl",
                    "DEFAULT_ADMIN_ROLE",
                    "bytes32",
                    bytes32(0),
                    "admin",
                    "role administration and diamondCut; the module business surface remains permissionless"
                );
            }
            variant.conditions = new string[](0);
            result.variants[i] = variant;
            result.deploymentContexts[i] = RecipeSpecLib.deploymentContext(
                "DeployERC5564Announcer",
                i == 0 ? "run()" : "run(address)",
                variant,
                i == 0 ? "buildCuts()" : "buildCuts(admin)"
            );
        }
    }

    /// @notice Deploys an ERC-5564 announcer diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @return announcer The deployed announcer diamond address.
    function run() external returns (address announcer) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts();
        announcer = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(address admin) external returns (address announcer) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        announcer = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
