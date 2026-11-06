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
import {ConstantProduct} from "@lattice/amm/ConstantProduct.sol";
import {ConstantProductInit} from "@lattice/amm/ConstantProductInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployConstantProduct
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a ConstantProduct AMM diamond: `ERC165Facet` + `AccessControl` +
///         `ConstantProduct` + {ConstantProductInit}. The ONE source of truth for what a constant-product pool
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on
///         {buildCuts}). `AccessControl` is part of the base recipe so pool administration is
///         `DEFAULT_ADMIN_ROLE`-gated; the pool is bound to its two ERC-20 reserve tokens at init.
contract DeployConstantProduct is BaseDeploy {
    /// @notice Builds the ConstantProduct pool diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param tokenA One of the two pool reserve tokens.
    /// @param tokenB The other pool reserve token.
    /// @return cuts The facet cuts (ERC165 + AccessControl + ConstantProduct + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {ConstantProductInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address tokenA, address tokenB)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("ConstantProductInit"), abi.encodeCall(ConstantProductInit.init, (admin, tokenA, tokenB))
        );
    }

    /// @notice Deploys a ConstantProduct pool diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The pool admin.
    /// @param tokenA One of the two pool reserve tokens.
    /// @param tokenB The other pool reserve token.
    /// @return pool The deployed pool diamond address.
    function run(address admin, address tokenA, address tokenB) external returns (address pool) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, tokenA, tokenB);
        pool = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployConstantProduct: unknown variant");
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("ConstantProduct");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cut plan, typed initializer tree and deployment inputs as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployConstantProduct", "script/base/amm/DeployConstantProduct.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployConstantProduct:buildCuts(address,address,address)";
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
            "tokenA",
            "address",
            "ERC20-reserve-token",
            "mock-ERC20-token-A",
            "enforced: nonzero and distinct from tokenB; caller authenticates the token and its transfer behavior"
        );
        variant.inputs[2] = RecipeParameter(
            "tokenB",
            "address",
            "ERC20-reserve-token",
            "mock-ERC20-token-B",
            "enforced: nonzero and distinct from tokenA; caller authenticates the token and its transfer behavior"
        );
        string[] memory bindings = new string[](3);
        bindings[0] = "admin";
        bindings[1] = "tokenA";
        bindings[2] = "tokenB";
        variant.initPlan = RecipeSpecLib.introspected(
            RecipeSpecLib.leaf("ConstantProductInit", "init(address,address,address)", variant.inputs, bindings), true
        );
        variant.authorities = new RecipeAuthority[](1);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl", "DEFAULT_ADMIN_ROLE", "bytes32", bytes32(0), "admin", "role administration and diamondCut"
        );
        variant.conditions = new string[](2);
        variant.conditions[0] =
            "initialization requires distinct nonzero tokens and sorts their addresses into token0 < token1; it does not authenticate token implementations";
        variant.conditions[1] = "caller: provide initial pool liquidity through the pool operations after deployment";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployConstantProduct", "run(address,address,address)", variant, "buildCuts(admin,tokenA,tokenB)"
        );
    }
}
