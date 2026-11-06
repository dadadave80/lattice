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
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {ERC721PausableInit} from "@lattice/tokens/ERC721/ERC721PausableInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC721Pausable
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a pausable ERC-721 token diamond: the base {DeployERC721} recipe
///         (ERC165 + ERC721 + {ERC721Init}), the {Pausable} facet (admin-gated `pause()`/`unpause()`), and the
///         {ERC721Pausable} facet, which REPLACES the base `transferFrom` and both `safeTransferFrom` overloads with
///         pause-gated variants. {ERC721PausableInit} registers IPausable and grants `admin` the DEFAULT_ADMIN_ROLE.
///         All inits run in one initializing window via {BaseDeploy._assembleMulti}.
/// @dev Admin-only: the pause authority must exist, so there is no immutable overload. The pause gates only the
///      three replaced selectors; {ERC721Burnable} or {ERC721Wrapper} cut next to it still burn and wrap while paused.
///      All inventory facets and initializers use the shared release helpers.
contract DeployERC721Pausable is TokenDeployBase {
    /// @notice Builds the pausable ERC-721 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name. @param symbol_ Token symbol. @param admin The pause/unpause and upgrade authority.
    /// @return cuts The facet cuts (ERC165 + ERC721 + DiamondLoupeFacet [base] + Pausable [Add] + ERC721Pausable
    ///         [Replace] + AccessControl + AccessControlDiamondCut).
    /// @return inits The initializers, run in order ({DeployERC721}'s {MultiInit} chain, {ERC721PausableInit}, then
    ///         {DiamondIntrospectionInit.initUpgradeable}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory name_, string memory symbol_, address admin)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (address baseInit, bytes memory baseCalldata) = _erc721BaseInit(name_, symbol_);

        inits = new address[](3);
        inits[0] = baseInit;
        inits[1] = _init("ERC721PausableInit");
        inits[2] = _init("DiamondIntrospectionInit");

        initCalldatas = new bytes[](3);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC721PausableInit.init, (admin));
        // The base chain registered the loupe flag; the cut facet is live too — advertise both.
        initCalldatas[2] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    /// @notice Deploys a pausable ERC-721 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(string memory name_, string memory symbol_, address admin) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, admin);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployERC721Pausable: unknown variant");
        RecipeFacet[] memory extension = new RecipeFacet[](4);
        extension[0] = RecipePlanLib.all("Pausable");
        extension[1] = RecipePlanLib.replaceAll("ERC721Pausable");
        extension[2] = RecipePlanLib.all("AccessControl");
        extension[3] = RecipePlanLib.all("AccessControlDiamondCut");
        return RecipePlanLib.append(TokenRecipePlans.erc721(false), extension);
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory seams) {
        seams = new RecipeSeam[](3);
        seams[0] = RecipePlanLib.seam2(
            "DeployERC721Pausable:transferFrom(address,address,uint256)",
            bytes4(keccak256("transferFrom(address,address,uint256)")),
            "ERC721",
            "ERC721Pausable",
            "ERC721Pausable",
            "the pausable mover must enforce pause checks on base transfers"
        );
        seams[1] = RecipePlanLib.seam2(
            "DeployERC721Pausable:safeTransferFrom(address,address,uint256)",
            bytes4(keccak256("safeTransferFrom(address,address,uint256)")),
            "ERC721",
            "ERC721Pausable",
            "ERC721Pausable",
            "the pausable mover must enforce pause checks on base transfers"
        );
        seams[2] = RecipePlanLib.seam2(
            "DeployERC721Pausable:safeTransferFrom(address,address,uint256,bytes)",
            bytes4(keccak256("safeTransferFrom(address,address,uint256,bytes)")),
            "ERC721",
            "ERC721Pausable",
            "ERC721Pausable",
            "the pausable mover must enforce pause checks on base transfers"
        );
    }

    function _recipeInitPlan(uint256, RecipeParameter[] memory inputs) private pure returns (RecipeInitStep[] memory) {
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
            RecipeParameter[] memory moduleParameters = new RecipeParameter[](1);
            string[] memory moduleBindings = new string[](1);
            moduleParameters[0] =
                RecipeParameter("admin_", "address", inputs[2].unit, inputs[2].example, inputs[2].rule);
            moduleBindings[0] = "admin";
            module = RecipeSpecLib.leaf("ERC721PausableInit", "init(address)", moduleParameters, moduleBindings);
        }
        RecipeInitStep[][] memory children = new RecipeInitStep[][](3);
        children[0] = base;
        children[1] = module;
        children[2] = RecipeSpecLib.emptyLeaf("DiamondIntrospectionInit", "initUpgradeable()");
        return RecipeSpecLib.wrap(children);
    }

    /// @notice Canonical cut/seam plans, exact initializer tree and deployment arguments as script-only data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC721Pausable", "script/base/tokens/DeployERC721Pausable.s.sol", 1);
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployERC721Pausable:buildCuts(string,string,address)";
        variant.buildSignature = "buildCuts(string,string,address)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Parallel;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](3);
        variant.inputs[0] = RecipeParameter("name_", "string", "metadata", "Example NFT", "no length constraint");
        variant.inputs[1] = RecipeParameter("symbol_", "string", "metadata", "EXNFT", "no length constraint");
        variant.inputs[2] = RecipeParameter(
            "admin",
            "address",
            "account",
            "0x00000000000000000000000000000000000000ad",
            "caller: choose a usable role and upgrade administrator; initialization permits the zero address"
        );
        variant.initPlan = _recipeInitPlan(0, variant.inputs);
        variant.authorities = new RecipeAuthority[](1);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "pause/unpause, role administration and diamondCut"
        );
        variant.conditions = new string[](2);
        variant.conditions[0] =
            "only the three replaced transfer selectors gain pause checks; separate burn, wrap or custom mint paths do not automatically inherit those checks";
        variant.conditions[1] =
        "admin controls pause/unpause and diamondCut through DEFAULT_ADMIN_ROLE; no separate mint role is granted";
        result.variants[0] = variant;
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployERC721Pausable", "run(string,string,address)", variant, "buildCuts(name_,symbol_,admin)"
        );
    }
}
