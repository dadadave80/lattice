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
import {ERC1155} from "@lattice/tokens/ERC1155/ERC1155.sol";
import {ERC1155Init} from "@lattice/tokens/ERC1155/ERC1155Init.sol";

/// @title DeployERC1155
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a base ERC-1155 token diamond: `ERC165Facet` + `ERC1155` + {ERC1155Init}.
///         The ONE source of truth for what a base ERC-1155 diamond is, shared by production (`run --broadcast`)
///         and the facet tests (which build on {buildCuts}, appending test-only helper facets). Extension tokens
///         extend these cuts with their additive facets, keeping this the canonical base.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut; deploy a new diamond to change
///      behavior. Use the ADMIN overload (`buildCuts(..., admin)` / `run(..., admin)`) for an upgradeable
///      deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployERC1155 is TokenDeployBase {
    /// @notice Builds the base ERC-1155 diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param uri_ Token URI template.
    /// @return cuts The facet cuts (ERC165 + ERC1155 + DiamondLoupeFacet).
    /// @return init The {MultiInit} running {ERC1155Init} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(string memory uri_)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _erc1155BaseInit(uri_);
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(string memory uri_, address admin)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(1), _recipeSeams(1));
        (init, initCalldata) =
            _withAdminUpgradeableIntrospection(_init("ERC1155Init"), abi.encodeCall(ERC1155Init.init, (uri_)), admin);
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant < 2, "DeployERC1155: unknown variant");
        return TokenRecipePlans.erc1155(variant == 1);
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cut plans, exact nested initialization and authorities as script data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC1155", "script/base/tokens/DeployERC1155.s.sol", 2);
        result.deploymentContexts = new RecipeDeploymentContext[](2);
        for (uint256 i; i < 2; ++i) {
            RecipeVariant memory variant;
            variant.id = i == 0 ? "DeployERC1155:buildCuts(string)" : "DeployERC1155:buildCuts(string,address)";
            variant.buildSignature = i == 0 ? "buildCuts(string)" : "buildCuts(string,address)";
            variant.proxyKind = RecipeProxyKind.Lattice;
            variant.initOutputKind = RecipeInitOutputKind.Single;
            variant.facets = _cutPlan(i);
            variant.seams = _recipeSeams(i);
            variant.inputs = new RecipeParameter[](i == 0 ? 1 : 2);
            variant.inputs[0] = RecipeParameter(
                "uri_",
                "string",
                "ERC1155-URI-template",
                "ipfs://example/{id}.json",
                "no nonempty or length constraint; caller supplies the intended metadata template"
            );
            if (i == 1) {
                variant.inputs[1] = RecipeParameter(
                    "admin",
                    "address",
                    "account",
                    "0x00000000000000000000000000000000000000ad",
                    "caller: choose a usable role and upgrade administrator; initialization permits the zero address"
                );
            }
            RecipeParameter[] memory baseParameters = new RecipeParameter[](1);
            baseParameters[0] = variant.inputs[0];
            string[] memory baseBindings = new string[](1);
            baseBindings[0] = "uri_";
            RecipeInitStep[] memory baseLeaf =
                RecipeSpecLib.leaf("ERC1155Init", "init(string)", baseParameters, baseBindings);
            variant.initPlan = i == 0
                ? RecipeSpecLib.introspected(baseLeaf, false)
                : RecipeSpecLib.adminIntrospected(baseLeaf, "admin");
            variant.authorities = new RecipeAuthority[](i == 0 ? 0 : 1);
            if (i == 1) {
                variant.authorities[0] = RecipeSpecLib.role(
                    "AccessControl",
                    "DEFAULT_ADMIN_ROLE",
                    "bytes32",
                    bytes32(0),
                    "admin",
                    "role administration and diamondCut; token approvals and burns retain their owner/operator checks"
                );
            }
            variant.conditions = new string[](1);
            variant.conditions[0] =
            "caller: add application mint logic separately; no public mint selector is cut by this recipe";
            result.variants[i] = variant;
            result.deploymentContexts[i] = RecipeSpecLib.deploymentContext(
                "DeployERC1155",
                i == 0 ? "run(string)" : "run(string,address)",
                variant,
                i == 0 ? "buildCuts(uri_)" : "buildCuts(uri_,admin)"
            );
        }
    }

    /// @notice Deploys a base ERC-1155 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @return token The deployed token diamond address.
    function run(string memory uri_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(uri_);
        token = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(string memory uri_, address admin) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(uri_, admin);
        token = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
