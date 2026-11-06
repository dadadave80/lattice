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
import {SuperchainETHBridgeAdapter} from "@lattice/crosschain/optimism/SuperchainETHBridgeAdapter.sol";
import {SuperchainETHBridgeAdapterInit} from "@lattice/crosschain/optimism/SuperchainETHBridgeAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeploySuperchainETHBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a `SuperchainETHBridge` interop adapter diamond: `ERC165Facet` +
///         `SuperchainETHBridgeAdapter` + {SuperchainETHBridgeAdapterInit}. The ONE source of truth for what the
///         adapter diamond is, shared by production (`run --broadcast`) and the facet tests (via {buildCuts}).
///         No `AccessControl` in the recipe: the adapter has no admin surface (the predeploy is a compile-time
///         constant and there is no config to gate).
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut; deploy a new diamond to change
///      behavior. Use the ADMIN overload (`buildCuts(..., admin)` / `run(..., admin)`) for an upgradeable
///      deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeploySuperchainETHBridgeAdapter is BaseDeploy {
    /// @notice Builds the adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @return cuts         The facet cuts (ERC165 + SuperchainETHBridgeAdapter).
    /// @return init         The {MultiInit} running {SuperchainETHBridgeAdapterInit} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts() public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withImmutableIntrospection(
            _init("SuperchainETHBridgeAdapterInit"), abi.encodeCall(SuperchainETHBridgeAdapterInit.init, ())
        );
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(1), _recipeSeams(1));
        (init, initCalldata) = _withAdminUpgradeableIntrospection(
            _init("SuperchainETHBridgeAdapterInit"), abi.encodeCall(SuperchainETHBridgeAdapterInit.init, ()), admin
        );
    }

    /// @notice Deploys a `SuperchainETHBridge` adapter diamond (broadcasting entrypoint for `forge script`).
    /// @return adapter The deployed adapter diamond address.
    function run() external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts();
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(address admin) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @dev The shared module cuts plus introspection; the admin variant appends its upgrade authority.
    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant < 2, "DeploySuperchainETHBridgeAdapter: unknown variant");
        facets = new RecipeFacet[](variant == 0 ? 3 : 5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("SuperchainETHBridgeAdapter");
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
            "DeploySuperchainETHBridgeAdapter", "script/base/crosschain/DeploySuperchainETHBridgeAdapter.s.sol", 2
        );
        result.deploymentContexts = new RecipeDeploymentContext[](2);
        for (uint256 i; i < 2; ++i) {
            RecipeVariant memory variant;
            variant.id = i == 0
                ? "DeploySuperchainETHBridgeAdapter:buildCuts()"
                : "DeploySuperchainETHBridgeAdapter:buildCuts(address)";
            variant.buildSignature = i == 0 ? "buildCuts()" : "buildCuts(address)";
            variant.proxyKind = RecipeProxyKind.Lattice;
            variant.initOutputKind = RecipeInitOutputKind.Single;
            variant.facets = _cutPlan(i);
            variant.seams = _recipeSeams(i);
            variant.inputs = new RecipeParameter[](i == 0 ? 0 : 1);
            RecipeParameter[] memory parameters = new RecipeParameter[](0);
            string[] memory bindings = new string[](0);
            RecipeInitStep[] memory module =
                RecipeSpecLib.leaf("SuperchainETHBridgeAdapterInit", "init()", parameters, bindings);
            if (i == 0) {
                variant.initPlan = RecipeSpecLib.introspected(module, false);
                variant.authorities = new RecipeAuthority[](0);
            } else {
                variant.inputs[0] = RecipeParameter(
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
                "caller: verify interop support and the fixed SUPERCHAIN_ETH_BRIDGE at 0x4200000000000000000000000000000000000024 on the target chain";
            result.variants[i] = variant;
            result.deploymentContexts[i] = RecipeSpecLib.deploymentContext(
                "DeploySuperchainETHBridgeAdapter",
                i == 0 ? "run()" : "run(address)",
                variant,
                i == 0 ? "buildCuts()" : "buildCuts(admin)"
            );
        }
    }
}
