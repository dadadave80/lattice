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
import {CircuitBreaker} from "@lattice/security/CircuitBreaker.sol";
import {CircuitBreakerInit} from "@lattice/security/CircuitBreakerInit.sol";

/// @title DeployCircuitBreaker
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a CircuitBreaker diamond: `ERC165Facet` + `AccessControl` +
///         `CircuitBreaker` + its released initializer. The ONE source of truth for what a circuit-breaker diamond
///         is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because `setThreshold`/`recordObservation`/`reset` are
///         `DEFAULT_ADMIN_ROLE`-gated.
contract DeployCircuitBreaker is BaseDeploy {
    /// @notice Builds the CircuitBreaker diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the breaker configuration).
    /// @return cuts The facet cuts (ERC165 + AccessControl + CircuitBreaker + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {CircuitBreakerInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("CircuitBreakerInit"), abi.encodeCall(CircuitBreakerInit.init, (admin))
        );
    }

    /// @dev The ordered facets shared by the builder and its exported recipe data.
    function _cutPlan(uint256) internal pure returns (RecipeFacet[] memory facets) {
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("CircuitBreaker");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cuts, typed initializer order and assigned authorities as script data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployCircuitBreaker", "script/base/security/DeployCircuitBreaker.s.sol", 1);
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployCircuitBreaker:buildCuts(address)";
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
        RecipeInitStep[] memory module = RecipeSpecLib.leaf("CircuitBreakerInit", "init(address)", parameters, bindings);
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
        result.deploymentContexts[0] =
            RecipeSpecLib.deploymentContext("DeployCircuitBreaker", "run(address)", variant, "buildCuts(admin)");
    }

    /// @notice Deploys a CircuitBreaker diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The breaker admin.
    /// @return breaker The deployed circuit-breaker diamond address.
    function run(address admin) external returns (address breaker) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        breaker = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
