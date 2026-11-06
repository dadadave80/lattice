// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {TokenDeployBase} from "@lattice-script/base/tokens/TokenDeployBase.s.sol";
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
import {TokenRecipePlans} from "@lattice-script/lib/TokenRecipePlans.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC721} from "@lattice/tokens/ERC721/ERC721.sol";
import {ERC721Init} from "@lattice/tokens/ERC721/ERC721Init.sol";

/// @title DeployERC721
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a base ERC-721 token diamond: `ERC165Facet` + `ERC721` + {ERC721Init}.
///         The ONE source of truth for what a base ERC-721 diamond is, shared by production (`run --broadcast`)
///         and the facet tests (which build on {buildCuts}, appending test-only helper facets). Extension
///         tokens extend these cuts with their additive facets, keeping this the canonical base. Mirrors the
///         {DeployERC20} template.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut; deploy a new diamond to change
///      behavior. Use the ADMIN overload (`buildCuts(..., admin)` / `run(..., admin)`) for an upgradeable
///      deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployERC721 is TokenDeployBase {
    /// @notice Builds the base ERC-721 diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param name_ Token name.
    /// @param symbol_ Token symbol.
    /// @return cuts The facet cuts (ERC165 + ERC721 + DiamondLoupeFacet).
    /// @return init The {MultiInit} running {ERC721Init} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(string memory name_, string memory symbol_)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _erc721BaseInit(name_, symbol_);
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(string memory name_, string memory symbol_, address admin)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(1), _recipeSeams(1));
        (init, initCalldata) = _withAdminUpgradeableIntrospection(
            _init("ERC721Init"), abi.encodeCall(ERC721Init.init, (name_, symbol_)), admin
        );
    }

    /// @notice Deploys a base ERC-721 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
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

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant < 2, "DeployERC721: unknown variant");
        return TokenRecipePlans.erc721(variant == 1);
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory seams) {
        seams = new RecipeSeam[](0);
    }

    function _recipeInitPlan(uint256 variant, RecipeParameter[] memory inputs)
        private
        pure
        returns (RecipeInitStep[] memory)
    {
        RecipeInitStep[] memory baseModule;
        {
            RecipeParameter[] memory baseModuleParameters = new RecipeParameter[](2);
            string[] memory baseModuleBindings = new string[](2);
            baseModuleParameters[0] =
                RecipeParameter("name_", "string", inputs[0].unit, inputs[0].example, inputs[0].rule);
            baseModuleBindings[0] = "name_";
            baseModuleParameters[1] =
                RecipeParameter("symbol_", "string", inputs[1].unit, inputs[1].example, inputs[1].rule);
            baseModuleBindings[1] = "symbol_";
            baseModule =
                RecipeSpecLib.leaf("ERC721Init", "init(string,string)", baseModuleParameters, baseModuleBindings);
        }
        if (variant == 0) return RecipeSpecLib.introspected(baseModule, false);
        return RecipeSpecLib.adminIntrospected(baseModule, "admin");
    }

    /// @notice Canonical cut/seam plans, exact initializer tree and deployment arguments as script-only data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC721", "script/base/tokens/DeployERC721.s.sol", 2);
        result.deploymentContexts = new RecipeDeploymentContext[](2);
        for (uint256 i; i < 2; ++i) {
            RecipeVariant memory variant;
            variant.id =
                i == 0 ? "DeployERC721:buildCuts(string,string)" : "DeployERC721:buildCuts(string,string,address)";
            variant.buildSignature = i == 0 ? "buildCuts(string,string)" : "buildCuts(string,string,address)";
            variant.proxyKind = RecipeProxyKind.Lattice;
            variant.initOutputKind = RecipeInitOutputKind.Single;
            variant.facets = _cutPlan(i);
            variant.seams = _recipeSeams(i);
            variant.inputs = new RecipeParameter[](i == 0 ? 2 : 3);
            variant.inputs[0] = RecipeParameter("name_", "string", "metadata", "Example NFT", "no length constraint");
            variant.inputs[1] = RecipeParameter("symbol_", "string", "metadata", "EXNFT", "no length constraint");
            if (i == 1) {
                variant.inputs[2] = RecipeParameter(
                    "admin",
                    "address",
                    "account",
                    "0x00000000000000000000000000000000000000ad",
                    "caller: choose a usable role and upgrade administrator; initialization permits the zero address"
                );
            }
            variant.initPlan = _recipeInitPlan(i, variant.inputs);
            variant.authorities = new RecipeAuthority[](i == 0 ? 0 : 1);
            if (i == 1) {
                variant.authorities[0] = RecipeSpecLib.role(
                    "AccessControl",
                    "DEFAULT_ADMIN_ROLE",
                    "bytes32",
                    bytes32(0),
                    "admin",
                    "role administration and diamondCut; no automatic mint authority or NFT ownership"
                );
            }
            variant.conditions = new string[](2);
            variant.conditions[0] =
                "the base recipe exposes no public mint; caller includes any application-specific mint surface in the reviewed initial composition";
            variant.conditions[1] = "the upgrade administrator receives no automatic NFT ownership or mint authority";
            result.variants[i] = variant;
            result.deploymentContexts[i] = RecipeSpecLib.deploymentContext(
                "DeployERC721",
                i == 0 ? "run(string,string)" : "run(string,string,address)",
                variant,
                i == 0 ? "buildCuts(name_,symbol_)" : "buildCuts(name_,symbol_,admin)"
            );
        }
    }
}
