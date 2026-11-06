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
import {PythAdapter} from "@lattice/oracles/pyth/PythAdapter.sol";
import {PythAdapterInit} from "@lattice/oracles/pyth/PythAdapterInit.sol";

/// @title DeployPythAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Pyth price-feed adapter diamond: `ERC165Facet` + `AccessControl` +
///         `PythAdapter` + {PythAdapterInit}. The ONE source of truth for what a Pyth adapter diamond is, shared
///         by production (`run --broadcast`) and the facet tests (which build on {buildCuts}). `AccessControl` is
///         part of the base recipe because the feed-registry setters and `setPyth` are `DEFAULT_ADMIN_ROLE`-gated.
///         Unlike the registry-only adapters, the Pyth contract reference is wired at init time.
contract DeployPythAdapter is BaseDeploy {
    /// @notice Builds the Pyth adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the feed registry and `setPyth`).
    /// @param pyth The Pyth contract the adapter reads prices from and forwards update fees to.
    /// @return cuts The facet cuts (ERC165 + AccessControl + PythAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {PythAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address pyth)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("PythAdapterInit"), abi.encodeCall(PythAdapterInit.init, (admin, pyth))
        );
    }

    function _cutPlan(uint256) internal pure returns (RecipeFacet[] memory facets) {
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("PythAdapter");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cuts, typed initializer bindings and deployment context as pure script data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployPythAdapter", "script/base/oracles/DeployPythAdapter.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployPythAdapter:buildCuts(address,address)";
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
            "caller: choose a usable role administrator and upgrade authority; initialization permits the zero address"
        );
        variant.inputs[1] = RecipeParameter(
            "pyth",
            "address",
            "Pyth-contract-address",
            "mock-or-target-configured-Pyth",
            "enforced at initialization: nonzero; caller authenticates the target-chain Pyth implementation"
        );
        string[] memory bindings = new string[](2);
        bindings[0] = "admin";
        bindings[1] = "pyth";
        variant.initPlan = RecipeSpecLib.introspected(
            RecipeSpecLib.leaf("PythAdapterInit", "init(address,address)", variant.inputs, bindings), true
        );
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
        "caller: register price IDs, staleness limits and confidence bounds after initialization";
        variant.conditions[1] =
        "caller: authenticate external service configuration; this recipe does not verify live providers";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployPythAdapter", "run(address,address)", variant, "buildCuts(admin,pyth)"
        );
    }

    /// @notice Deploys a Pyth adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The feed-registry admin.
    /// @param pyth The Pyth contract reference.
    /// @return adapter The deployed Pyth adapter diamond address.
    function run(address admin, address pyth) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, pyth);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
