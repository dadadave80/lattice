// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {TokenDeployBase} from "@lattice-script/base/tokens/TokenDeployBase.s.sol";
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
import {TokenRecipePlans} from "@lattice-script/lib/TokenRecipePlans.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Init} from "@lattice/tokens/ERC20/ERC20Init.sol";

/// @title DeployERC20
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a base ERC-20 token diamond: `ERC165Facet` + `ERC20` + {ERC20Init}. The
///         ONE source of truth for what a base ERC-20 diamond is, shared by production (`run --broadcast`) and
///         the facet tests (which build on {buildCuts}, appending test-only helper facets). Extension tokens
///         extend these cuts with their additive facets (Burnable/Capped/…), keeping this the canonical base.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut; deploy a new diamond to change
///      behavior. Use the ADMIN overload (`buildCuts(..., admin)` / `run(..., admin)`) for an upgradeable
///      deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployERC20 is TokenDeployBase {
    /// @notice Builds the base ERC-20 diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param name_ Token name.
    /// @param symbol_ Token symbol.
    /// @return cuts The facet cuts (ERC165 + ERC20 + DiamondLoupeFacet).
    /// @return init The {MultiInit} running {ERC20Init} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(string memory name_, string memory symbol_)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) =
            _withImmutableIntrospection(_init("ERC20Init"), abi.encodeCall(ERC20Init.init, (name_, symbol_)));
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(string memory name_, string memory symbol_, address admin)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(1), _recipeSeams(1));
        (init, initCalldata) = _withAdminUpgradeableIntrospection(
            _init("ERC20Init"), abi.encodeCall(ERC20Init.init, (name_, symbol_)), admin
        );
    }

    function _cutPlan(uint256 variant) internal pure virtual returns (RecipeFacet[] memory) {
        require(variant < 2, "DeployERC20: unknown variant");
        return TokenRecipePlans.erc20(variant == 1);
    }

    function _recipeSeams(uint256) internal pure virtual returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Both canonical builder variants, using the same cut plans as buildCuts and explicit init trees.
    function recipeSpec() public pure virtual returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC20", "script/base/tokens/DeployERC20.s.sol", 2);
        result.deploymentContexts = new RecipeDeploymentContext[](2);
        for (uint256 i; i < 2; ++i) {
            RecipeVariant memory variant;
            variant.id =
                i == 0 ? "DeployERC20:buildCuts(string,string)" : "DeployERC20:buildCuts(string,string,address)";
            variant.buildSignature = i == 0 ? "buildCuts(string,string)" : "buildCuts(string,string,address)";
            variant.proxyKind = RecipeProxyKind.Lattice;
            variant.initOutputKind = RecipeInitOutputKind.Single;
            variant.facets = _cutPlan(i);
            variant.seams = _recipeSeams(i);
            variant.inputs = new RecipeParameter[](i == 0 ? 2 : 3);
            variant.inputs[0] = RecipeParameter("name_", "string", "metadata", "Example Token", "no length constraint");
            variant.inputs[1] = RecipeParameter("symbol_", "string", "metadata", "EXM", "no length constraint");
            RecipeParameter[] memory parameters = new RecipeParameter[](2);
            parameters[0] = variant.inputs[0];
            parameters[1] = variant.inputs[1];
            string[] memory bindings = new string[](2);
            bindings[0] = "name_";
            bindings[1] = "symbol_";
            RecipeInitStep[] memory module =
                RecipeSpecLib.leaf("ERC20Init", "init(string,string)", parameters, bindings);
            if (i == 0) {
                variant.initPlan = RecipeSpecLib.introspected(module, false);
                variant.authorities = new RecipeAuthority[](0);
            } else {
                variant.inputs[2] = RecipeParameter(
                    "admin",
                    "address",
                    "account",
                    "0x00000000000000000000000000000000000000ad",
                    "caller: choose a usable upgrade authority; initialization permits the zero address"
                );
                variant.initPlan = RecipeSpecLib.adminIntrospected(module, "admin");
                variant.authorities = new RecipeAuthority[](1);
                variant.authorities[0] = RecipeSpecLib.role(
                    "AccessControl",
                    "DEFAULT_ADMIN_ROLE",
                    "bytes32",
                    bytes32(0),
                    "admin",
                    "bootstrap role administration and diamondCut"
                );
            }
            variant.conditions = new string[](0);
            result.variants[i] = variant;
            result.deploymentContexts[i] = RecipeSpecLib.deploymentContext(
                "DeployERC20",
                i == 0 ? "run(string,string)" : "run(string,string,address)",
                variant,
                i == 0 ? "buildCuts(name_,symbol_)" : "buildCuts(name_,symbol_,admin)"
            );
        }
    }

    /// @notice Deploys a base ERC-20 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @return token The deployed token diamond address.
    function run(string memory name_, string memory symbol_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(name_, symbol_);
        token = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(string memory name_, string memory symbol_, address admin) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(name_, symbol_, admin);
        token = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
