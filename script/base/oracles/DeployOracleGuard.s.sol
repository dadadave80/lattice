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
import {OracleGuard} from "@lattice/oracles/OracleGuard.sol";
import {OracleGuardInit} from "@lattice/oracles/OracleGuardInit.sol";

/// @title DeployOracleGuard
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a standalone OracleGuard diamond: `ERC165Facet` + `AccessControl` +
///         `OracleGuard` + {OracleGuardInit} + {AccessControlInit}. The guard reads the adapter diamond each key is
///         configured with, so it fronts any existing Lattice price adapter without touching it. To guard an
///         adapter in place instead, cut the `OracleGuard` facet into the adapter's diamond, run {OracleGuardInit}
///         next to the adapter's init, and configure keys with that diamond as the oracle. `AccessControl` is
///         part of the base recipe because every setter is `DEFAULT_ADMIN_ROLE`-gated. No `Receive`: the guard
///         never holds value.
contract DeployOracleGuard is BaseDeploy {
    /// @notice Builds the OracleGuard diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return cuts The facet cuts (ERC165 + AccessControl + OracleGuard + DiamondLoupeFacet +
    ///         AccessControlDiamondCut).
    /// @return init The {MultiInit} running {OracleGuardInit}, {AccessControlInit}, then
    ///         {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withAdminUpgradeableIntrospection(
            _init("OracleGuardInit"), abi.encodeCall(OracleGuardInit.init, ()), admin
        );
    }

    function _cutPlan(uint256) internal pure returns (RecipeFacet[] memory facets) {
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("OracleGuard");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cuts, typed initializer bindings and deployment context as pure script data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployOracleGuard", "script/base/oracles/DeployOracleGuard.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployOracleGuard:buildCuts(address)";
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
            "caller: choose a usable role administrator and upgrade authority; initialization permits the zero address"
        );
        variant.initPlan =
            RecipeSpecLib.adminIntrospected(RecipeSpecLib.emptyLeaf("OracleGuardInit", "init()"), "admin");
        variant.authorities = new RecipeAuthority[](1);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "module configuration, role administration and diamondCut"
        );
        variant.conditions = new string[](2);
        variant.conditions[0] =
        "caller: configure guarded oracle keys, bounds and any sequencer feed after initialization";
        variant.conditions[1] =
        "caller: authenticate external service configuration; this recipe does not verify live providers";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] =
            RecipeSpecLib.deploymentContext("DeployOracleGuard", "run(address)", variant, "buildCuts(admin)");
    }

    /// @notice Deploys an OracleGuard diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The guard admin.
    /// @return guard The deployed OracleGuard diamond address.
    function run(address admin) external returns (address guard) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        guard = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
