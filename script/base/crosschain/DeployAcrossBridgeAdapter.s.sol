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
import {AcrossBridgeAdapter} from "@lattice/crosschain/across/AcrossBridgeAdapter.sol";
import {AcrossBridgeAdapterInit} from "@lattice/crosschain/across/AcrossBridgeAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployAcrossBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an Across v3 token-bridge diamond: `ERC165Facet` + `AcrossBridgeAdapter`
///         + {AcrossBridgeAdapterInit}. The ONE source of truth for what an Across adapter diamond is, shared
///         by production (`run --broadcast`) and the facet tests (which build on {buildCuts}). Unlike the CCTP
///         recipe there is NO `AccessControl` cut: the adapter has no admin surface (the SpokePool is wired
///         once at init and Across chain ids are passed raw by callers — no domain table to manage). The
///         reentrancy guard is seeded inside {AcrossBridgeAdapterInit} (storage-only, no facet cut needed).
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut; deploy a new diamond to change
///      behavior. Use the ADMIN overload (`buildCuts(..., admin)` / `run(..., admin)`) for an upgradeable
///      deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployAcrossBridgeAdapter is BaseDeploy {
    /// @notice Builds the Across adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param spokePool The LOCAL chain's canonical Across v3 SpokePool.
    /// @return cuts         The facet cuts (ERC165 + AcrossBridgeAdapter).
    /// @return init         The {MultiInit} running {AcrossBridgeAdapterInit} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address spokePool)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withImmutableIntrospection(
            _init("AcrossBridgeAdapterInit"), abi.encodeCall(AcrossBridgeAdapterInit.init, (spokePool))
        );
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(address spokePool, address admin)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(1), _recipeSeams(1));
        (init, initCalldata) = _withAdminUpgradeableIntrospection(
            _init("AcrossBridgeAdapterInit"), abi.encodeCall(AcrossBridgeAdapterInit.init, (spokePool)), admin
        );
    }

    /// @notice Deploys an Across adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param spokePool The LOCAL chain's canonical Across v3 SpokePool.
    /// @return adapter The deployed Across adapter diamond address.
    function run(address spokePool) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(spokePool);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(address spokePool, address admin) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(spokePool, admin);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @dev The shared module cuts plus introspection; the admin variant appends its upgrade authority.
    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant < 2, "DeployAcrossBridgeAdapter: unknown variant");
        facets = new RecipeFacet[](variant == 0 ? 3 : 5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AcrossBridgeAdapter");
        facets[2] = RecipePlanLib.all("DiamondLoupeFacet");
        if (variant == 1) {
            facets[3] = RecipePlanLib.all("AccessControl");
            facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
        }
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical builder variants and exact ordered initializer calls as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec(
            "DeployAcrossBridgeAdapter", "script/base/crosschain/DeployAcrossBridgeAdapter.s.sol", 2
        );
        result.deploymentContexts = new RecipeDeploymentContext[](2);
        for (uint256 i; i < 2; ++i) {
            RecipeVariant memory variant;
            variant.id = i == 0
                ? "DeployAcrossBridgeAdapter:buildCuts(address)"
                : "DeployAcrossBridgeAdapter:buildCuts(address,address)";
            variant.buildSignature = i == 0 ? "buildCuts(address)" : "buildCuts(address,address)";
            variant.proxyKind = RecipeProxyKind.Lattice;
            variant.initOutputKind = RecipeInitOutputKind.Single;
            variant.facets = _cutPlan(i);
            variant.seams = _recipeSeams(i);
            variant.inputs = new RecipeParameter[](i == 0 ? 1 : 2);
            variant.inputs[0] = RecipeParameter(
                "spokePool",
                "address",
                "Across-v3-SpokePool",
                "target-configured-spoke-pool",
                "enforced: nonzero; caller authenticates the local canonical SpokePool and its chain support"
            );
            RecipeParameter[] memory parameters = new RecipeParameter[](1);
            parameters[0] = variant.inputs[0];
            string[] memory bindings = new string[](1);
            bindings[0] = "spokePool";
            RecipeInitStep[] memory module =
                RecipeSpecLib.leaf("AcrossBridgeAdapterInit", "init(address)", parameters, bindings);
            if (i == 0) {
                variant.initPlan = RecipeSpecLib.introspected(module, false);
                variant.authorities = new RecipeAuthority[](0);
            } else {
                variant.inputs[1] = RecipeParameter(
                    "admin",
                    "address",
                    "account",
                    "0x00000000000000000000000000000000000000ad",
                    "caller: choose a usable role and upgrade administrator; initialization permits the zero address"
                );
                variant.initPlan = RecipeSpecLib.adminIntrospected(module, "admin");
                variant.authorities = new RecipeAuthority[](1);
                variant.authorities[0] = RecipeSpecLib.role(
                    "AccessControl",
                    "DEFAULT_ADMIN_ROLE",
                    "bytes32",
                    bytes32(0),
                    "admin",
                    "role administration and diamondCut through the admin-only wrapper"
                );
            }
            variant.conditions = new string[](1);
            variant.conditions[0] =
                "caller: pass raw Across destination chain IDs accepted by the configured SpokePool; this recipe creates no chain-domain table";
            result.variants[i] = variant;
            result.deploymentContexts[i] = RecipeSpecLib.deploymentContext(
                "DeployAcrossBridgeAdapter",
                i == 0 ? "run(address)" : "run(address,address)",
                variant,
                i == 0 ? "buildCuts(spokePool)" : "buildCuts(spokePool,admin)"
            );
        }
    }
}
