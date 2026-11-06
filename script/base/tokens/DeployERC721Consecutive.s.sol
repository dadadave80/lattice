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
import {ERC721ConsecutiveInit} from "@lattice/tokens/ERC721/ERC721ConsecutiveInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC721Consecutive
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-721 token diamond with ERC-2309 batch mints at creation: the base
///         {DeployERC721} recipe (ERC165 + ERC721 + {ERC721Init}) plus {ERC721ConsecutiveInit}, which mints
///         `amounts[i]` consecutive ids from `firstId` to `receivers[i]`. Batch minting adds no facet: the base
///         {ERC721} facet reads batch ownership through {ERC721Lib}. All inits run in the diamond's first
///         initialization via {BaseDeploy._assembleMulti}, the only window in which a batch may mint.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut (the inherited base recipe provides the
///      loupe); deploy a new diamond to change behavior. Use the ADMIN overload for an upgradeable deployment gated on
///      `DEFAULT_ADMIN_ROLE`; an upgrade cut cannot batch mint.
///      Do not add {ERC721Enumerable} or {ERC721Votes}: either init order reverts. {ERC721Pausable},
///      {ERC721Burnable}, {ERC721URIStorage}, {ERC721Wrapper} and {ERC2981} compose. Add no init that single-mints:
///      mint after the diamond is initialized.
contract DeployERC721Consecutive is TokenDeployBase {
    /// @notice Builds the batch-minted ERC-721 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name. @param symbol_ Token symbol.
    /// @param firstId The first batch-minted id. @param receivers Each batch's owner.
    /// @param amounts Each batch's size, at most 5000.
    /// @return cuts The facet cuts (ERC165 + ERC721 + DiamondLoupeFacet).
    /// @return inits The initializers, run in order ({DeployERC721}'s {MultiInit} chain, then
    ///         {ERC721ConsecutiveInit}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(
        string memory name_,
        string memory symbol_,
        uint96 firstId,
        address[] memory receivers,
        uint96[] memory amounts
    ) public returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (inits, initCalldatas) = _buildInitializers(name_, symbol_, firstId, receivers, amounts);
    }

    /// @notice Deploys a batch-minted ERC-721 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(
        string memory name_,
        string memory symbol_,
        uint96 firstId,
        address[] memory receivers,
        uint96[] memory amounts
    ) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, firstId, receivers, amounts);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(
        string memory name_,
        string memory symbol_,
        uint96 firstId,
        address[] memory receivers,
        uint96[] memory amounts,
        address admin
    ) public returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) {
        cuts = _materialize(_cutPlan(1), _recipeSeams(1));
        (address[] memory defInits, bytes[] memory defCalldatas) =
            _buildInitializers(name_, symbol_, firstId, receivers, amounts);
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
    function run(
        string memory name_,
        string memory symbol_,
        uint96 firstId,
        address[] memory receivers,
        uint96[] memory amounts,
        address admin
    ) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, firstId, receivers, amounts, admin);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }

    /// @dev Resolves only the original ordered initializer sequence after complete-plan validation.
    function _buildInitializers(
        string memory name_,
        string memory symbol_,
        uint96 firstId,
        address[] memory receivers,
        uint96[] memory amounts
    ) internal returns (address[] memory inits, bytes[] memory initCalldatas) {
        (address baseInit, bytes memory baseCalldata) = _erc721BaseInit(name_, symbol_);
        inits = new address[](2);
        inits[0] = baseInit;
        inits[1] = _init("ERC721ConsecutiveInit");

        initCalldatas = new bytes[](2);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC721ConsecutiveInit.init, (firstId, receivers, amounts));
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant < 2, "DeployERC721Consecutive: unknown variant");
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
        RecipeInitStep[] memory base = RecipeSpecLib.introspected(baseModule, false);
        RecipeInitStep[] memory module;
        {
            RecipeParameter[] memory moduleParameters = new RecipeParameter[](3);
            string[] memory moduleBindings = new string[](3);
            moduleParameters[0] =
                RecipeParameter("firstId", "uint96", inputs[2].unit, inputs[2].example, inputs[2].rule);
            moduleBindings[0] = "firstId";
            moduleParameters[1] =
                RecipeParameter("receivers", "address[]", inputs[3].unit, inputs[3].example, inputs[3].rule);
            moduleBindings[1] = "receivers";
            moduleParameters[2] =
                RecipeParameter("amounts", "uint96[]", inputs[4].unit, inputs[4].example, inputs[4].rule);
            moduleBindings[2] = "amounts";
            module = RecipeSpecLib.leaf(
                "ERC721ConsecutiveInit", "init(uint96,address[],uint96[])", moduleParameters, moduleBindings
            );
        }
        RecipeInitStep[][] memory children = new RecipeInitStep[][](variant == 0 ? 2 : 4);
        children[0] = base;
        children[1] = module;
        if (variant == 1) {
            RecipeInitStep[] memory adminStep;
            {
                RecipeParameter[] memory adminStepParameters = new RecipeParameter[](1);
                string[] memory adminStepBindings = new string[](1);
                adminStepParameters[0] =
                    RecipeParameter("admin", "address", inputs[5].unit, inputs[5].example, inputs[5].rule);
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
        result = RecipeSpecLib.spec("DeployERC721Consecutive", "script/base/tokens/DeployERC721Consecutive.s.sol", 2);
        result.deploymentContexts = new RecipeDeploymentContext[](2);
        for (uint256 i; i < 2; ++i) {
            RecipeVariant memory variant;
            variant.id = i == 0
                ? "DeployERC721Consecutive:buildCuts(string,string,uint96,address[],uint96[])"
                : "DeployERC721Consecutive:buildCuts(string,string,uint96,address[],uint96[],address)";
            variant.buildSignature = i == 0
                ? "buildCuts(string,string,uint96,address[],uint96[])"
                : "buildCuts(string,string,uint96,address[],uint96[],address)";
            variant.proxyKind = RecipeProxyKind.Lattice;
            variant.initOutputKind = RecipeInitOutputKind.Parallel;
            variant.facets = _cutPlan(i);
            variant.seams = _recipeSeams(i);
            variant.inputs = new RecipeParameter[](i == 0 ? 5 : 6);
            variant.inputs[0] = RecipeParameter("name_", "string", "metadata", "Example NFT", "no length constraint");
            variant.inputs[1] = RecipeParameter("symbol_", "string", "metadata", "EXNFT", "no length constraint");
            variant.inputs[2] = RecipeParameter(
                "firstId",
                "uint96",
                "token-id",
                "0",
                "enforced: firstId plus the cumulative minted amount must fit uint96; zero total minting is allowed"
            );
            variant.inputs[3] = RecipeParameter(
                "receivers",
                "address[]",
                "batch-owner-accounts",
                "[\"0x000000000000000000000000000000000000beef\"]",
                "enforced: length equals amounts; receivers[i] is nonzero only when amounts[i] is positive; no receiver hook is called"
            );
            variant.inputs[4] = RecipeParameter(
                "amounts",
                "uint96[]",
                "token-counts",
                "[3]",
                "enforced: length equals receivers; every positive batch is at most 5000; cumulative next-id arithmetic must fit uint96; zero batches are no-ops"
            );
            if (i == 1) {
                variant.inputs[5] = RecipeParameter(
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
            variant.conditions = new string[](5);
            variant.conditions[0] =
                "enforced: first native initialization window with initialized version 1; this batch initializer cannot be used in a later reinitializer upgrade";
            variant.conditions[1] =
                "zero batches mint nothing and allow a zero receiver; each positive batch requires a nonzero receiver and size at most 5000";
            variant.conditions[2] =
                "enforced: checked uint96 next-id arithmetic requires firstId + sum(amounts) <= type(uint96).max; the largest minted id is at most type(uint96).max - 1";
            variant.conditions[3] =
                "caller: never single-mint during this first initialization, in any init order; batch minting must not be combined with Enumerable or Votes";
            variant.conditions[4] =
                "batches add no facet, emit ConsecutiveTransfer and call no ERC721 receiver hook; recipients receive NFTs, not an administrative role";
            result.variants[i] = variant;
            result.deploymentContexts[i] = RecipeSpecLib.deploymentContext(
                "DeployERC721Consecutive",
                i == 0
                    ? "run(string,string,uint96,address[],uint96[])"
                    : "run(string,string,uint96,address[],uint96[],address)",
                variant,
                i == 0
                    ? "buildCuts(name_,symbol_,firstId,receivers,amounts)"
                    : "buildCuts(name_,symbol_,firstId,receivers,amounts,admin)"
            );
        }
    }
}
