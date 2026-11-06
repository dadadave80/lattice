// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC721} from "@lattice-script/base/tokens/DeployERC721.s.sol";
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
import {AccessControlInit} from "@lattice/access/AccessControlInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC721Burnable} from "@lattice/tokens/ERC721/ERC721Burnable.sol";
import {ERC721BurnableInit} from "@lattice/tokens/ERC721/ERC721BurnableInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC721Burnable
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a burnable ERC-721 token diamond: the base {DeployERC721} recipe
///         (ERC165 + ERC721 + {ERC721Init}) plus the additive {ERC721Burnable} facet and its {ERC721BurnableInit}.
///         `buildCuts` is the broadcast-free primitive the burnable facet test reuses; `run` broadcasts. Both
///         inits run in one initializing window via {BaseDeploy._assembleMulti}.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut (the inherited base recipe provides the
///      loupe); deploy a new diamond to change behavior. Use the ADMIN overload (`buildCuts(..., admin)` /
///      `run(..., admin)`) for an upgradeable deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployERC721Burnable is TokenDeployBase {
    /// @notice Builds the burnable ERC-721 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name. @param symbol_ Token symbol.
    /// @return cuts The facet cuts (ERC165 + ERC721 + DiamondLoupeFacet + ERC721Burnable).
    /// @return inits The initializers, run in order ({DeployERC721}'s {MultiInit} chain, then {ERC721BurnableInit}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory name_, string memory symbol_)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (inits, initCalldatas) = _buildInitializers(name_, symbol_);
    }

    /// @notice Deploys a burnable ERC-721 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(string memory name_, string memory symbol_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) = buildCuts(name_, symbol_);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(string memory name_, string memory symbol_, address admin)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        cuts = _materialize(_cutPlan(1), _recipeSeams(1));
        (address[] memory defInits, bytes[] memory defCalldatas) = _buildInitializers(name_, symbol_);
        inits = new address[](defInits.length + 2);
        for (uint256 i; i < defInits.length; ++i) {
            inits[i] = defInits[i];
        }
        inits[defInits.length] = _init("AccessControlInit");
        inits[defInits.length + 1] = _init("DiamondIntrospectionInit");

        initCalldatas = new bytes[](defCalldatas.length + 2);
        for (uint256 i; i < defCalldatas.length; ++i) {
            initCalldatas[i] = defCalldatas[i];
        }
        initCalldatas[defCalldatas.length] = abi.encodeCall(AccessControlInit.init, (admin));
        // The base chain registered the loupe flag; the cut facet is live too — advertise both.
        initCalldatas[defCalldatas.length + 1] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(string memory name_, string memory symbol_, address admin) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, admin);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }

    /// @dev Resolves only the original ordered initializer sequence after complete-plan validation.
    function _buildInitializers(string memory name_, string memory symbol_)
        internal
        returns (address[] memory inits, bytes[] memory initCalldatas)
    {
        (address baseInit, bytes memory baseCalldata) = _erc721BaseInit(name_, symbol_);
        inits = new address[](2);
        inits[0] = baseInit;
        inits[1] = _init("ERC721BurnableInit");

        initCalldatas = new bytes[](2);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC721BurnableInit.init, ());
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant < 2, "DeployERC721Burnable: unknown variant");
        RecipeFacet[] memory extension = new RecipeFacet[](variant == 0 ? 1 : 3);
        extension[0] = RecipePlanLib.all("ERC721Burnable");
        if (variant == 1) {
            extension[1] = RecipePlanLib.all("AccessControl");
            extension[2] = RecipePlanLib.all("AccessControlDiamondCut");
        }
        return RecipePlanLib.append(TokenRecipePlans.erc721(false), extension);
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
        RecipeInitStep[] memory base = RecipeSpecLib.introspected(baseModule, false);
        RecipeInitStep[] memory module = RecipeSpecLib.emptyLeaf("ERC721BurnableInit", "init()");
        RecipeInitStep[][] memory children = new RecipeInitStep[][](variant == 0 ? 2 : 4);
        children[0] = base;
        children[1] = module;
        if (variant == 1) {
            RecipeInitStep[] memory adminStep;
            {
                RecipeParameter[] memory adminStepParameters = new RecipeParameter[](1);
                string[] memory adminStepBindings = new string[](1);
                adminStepParameters[0] =
                    RecipeParameter("admin", "address", inputs[2].unit, inputs[2].example, inputs[2].rule);
                adminStepBindings[0] = "admin";
                adminStep =
                    RecipeSpecLib.leaf("AccessControlInit", "init(address)", adminStepParameters, adminStepBindings);
            }
            children[2] = adminStep;
            children[3] = RecipeSpecLib.emptyLeaf("DiamondIntrospectionInit", "initUpgradeable()");
        }
        return RecipeSpecLib.wrap(children);
    }

    /// @notice Canonical cut/seam plans, exact initializer tree and deployment arguments as script-only data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC721Burnable", "script/base/tokens/DeployERC721Burnable.s.sol", 2);
        result.deploymentContexts = new RecipeDeploymentContext[](2);
        for (uint256 i; i < 2; ++i) {
            RecipeVariant memory variant;
            variant.id = i == 0
                ? "DeployERC721Burnable:buildCuts(string,string)"
                : "DeployERC721Burnable:buildCuts(string,string,address)";
            variant.buildSignature = i == 0 ? "buildCuts(string,string)" : "buildCuts(string,string,address)";
            variant.proxyKind = RecipeProxyKind.Lattice;
            variant.initOutputKind = RecipeInitOutputKind.Parallel;
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
                "burn checks ERC721 owner/approval authorization; upgrade administration grants no NFT ownership or mint authority";
            variant.conditions[1] =
            "caller: do not combine this base-library burn path with Enumerable or Votes movement accounting";
            result.variants[i] = variant;
            result.deploymentContexts[i] = RecipeSpecLib.deploymentContext(
                "DeployERC721Burnable",
                i == 0 ? "run(string,string)" : "run(string,string,address)",
                variant,
                i == 0 ? "buildCuts(name_,symbol_)" : "buildCuts(name_,symbol_,admin)"
            );
        }
    }
}
