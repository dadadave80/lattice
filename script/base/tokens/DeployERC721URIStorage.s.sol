// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
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
import {TokenRecipePlans} from "@lattice-script/lib/TokenRecipePlans.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC721} from "@lattice/tokens/ERC721/ERC721.sol";
import {ERC721Init} from "@lattice/tokens/ERC721/ERC721Init.sol";
import {ERC721URIStorage} from "@lattice/tokens/ERC721/ERC721URIStorage.sol";
import {ERC721URIStorageInit} from "@lattice/tokens/ERC721/ERC721URIStorageInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC721URIStorage
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-721 diamond with per-token URI storage (EIP-4906):
///         `ERC165Facet` + `ERC721` + `ERC721URIStorage` + `AccessControl`, seeded by {ERC721Init} +
///         {ERC721URIStorageInit} run together in one initializing window via {MultiInit}
///         (see {BaseDeploy._assembleMulti}).
/// @dev Each facet owns ONLY its own selectors (the composability principle): the base `ERC721` facet exposes the
///      ERC-721 surface, and `ERC721URIStorage` is a MIXED cut over it — it REPLACEs `tokenURI` (per-token URI
///      storage) and ADDs `setTokenURI`. `AccessControl` is included because `setTokenURI` is gated on
///      `DEFAULT_ADMIN_ROLE` (bootstrapped by {ERC721URIStorageInit}), so a production deployment can manage that
///      admin.
contract DeployERC721URIStorage is BaseDeploy {
    /// @notice Builds the URI-storage ERC-721 diamond cuts + ordered initializers (no broadcast, no proxy).
    /// @param name_ Token name. @param symbol_ Token symbol. @param admin_ The metadata admin (DEFAULT_ADMIN_ROLE).
    /// @return cuts The facet cuts (ERC165 + ERC721 + ERC721URIStorage[Add setTokenURI, Replace tokenURI] +
    ///         AccessControl + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return inits The initializer contracts ({ERC721Init}, {ERC721URIStorageInit}, then
    ///         {DiamondIntrospectionInit.initUpgradeable}), run in order via {MultiInit}.
    /// @return initCalldatas The calldata for each initializer.
    function buildCuts(string memory name_, string memory symbol_, address admin_)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));

        inits = new address[](3);
        inits[0] = _init("ERC721Init");
        inits[1] = _init("ERC721URIStorageInit");
        inits[2] = _init("DiamondIntrospectionInit");

        initCalldatas = new bytes[](3);
        initCalldatas[0] = abi.encodeCall(ERC721Init.init, (name_, symbol_));
        initCalldatas[1] = abi.encodeCall(ERC721URIStorageInit.init, (admin_));
        initCalldatas[2] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    /// @notice The single `setTokenURI` selector ADDed by the URI-storage facet.
    function _setTokenURI() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = ERC721URIStorage.setTokenURI.selector;
    }

    /// @notice The single `tokenURI` selector the URI-storage facet REPLACEs on the base ERC-721 facet.
    function _tokenURI() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = ERC721URIStorage.tokenURI.selector;
    }

    /// @notice Deploys a URI-storage ERC-721 token diamond (broadcasting entrypoint for `forge script`).
    /// @return token The deployed token diamond address.
    function run(string memory name_, string memory symbol_, address admin_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, admin_);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployERC721URIStorage: unknown variant");
        RecipeFacet[] memory base = TokenRecipePlans.erc721(false);
        facets = new RecipeFacet[](7);
        facets[0] = base[0];
        facets[1] = base[1];
        facets[2] = RecipePlanLib.only("ERC721URIStorage", FacetCutAction.Add, _setTokenURI());
        facets[3] = RecipePlanLib.only("ERC721URIStorage", FacetCutAction.Replace, _tokenURI());
        facets[4] = RecipePlanLib.all("AccessControl");
        facets[5] = base[2];
        facets[6] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory seams) {
        seams = new RecipeSeam[](1);
        seams[0] = RecipePlanLib.seam2(
            "DeployERC721URIStorage:tokenURI(uint256)",
            bytes4(keccak256("tokenURI(uint256)")),
            "ERC721",
            "ERC721URIStorage",
            "ERC721URIStorage",
            "per-token URI storage must own tokenURI over the base metadata view"
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
        RecipeInitStep[] memory module;
        {
            RecipeParameter[] memory moduleParameters = new RecipeParameter[](1);
            string[] memory moduleBindings = new string[](1);
            moduleParameters[0] =
                RecipeParameter("admin_", "address", inputs[2].unit, inputs[2].example, inputs[2].rule);
            moduleBindings[0] = "admin_";
            module = RecipeSpecLib.leaf("ERC721URIStorageInit", "init(address)", moduleParameters, moduleBindings);
        }
        RecipeInitStep[][] memory children = new RecipeInitStep[][](3);
        children[0] = baseModule;
        children[1] = module;
        children[2] = RecipeSpecLib.emptyLeaf("DiamondIntrospectionInit", "initUpgradeable()");
        return RecipeSpecLib.wrap(children);
    }

    /// @notice Canonical cut/seam plans, exact initializer tree and deployment arguments as script-only data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC721URIStorage", "script/base/tokens/DeployERC721URIStorage.s.sol", 1);
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployERC721URIStorage:buildCuts(string,string,address)";
        variant.buildSignature = "buildCuts(string,string,address)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Parallel;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](3);
        variant.inputs[0] = RecipeParameter("name_", "string", "metadata", "Example NFT", "no length constraint");
        variant.inputs[1] = RecipeParameter("symbol_", "string", "metadata", "EXNFT", "no length constraint");
        variant.inputs[2] = RecipeParameter(
            "admin_",
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
            "admin_",
            "setTokenURI, role administration and diamondCut"
        );
        variant.conditions = new string[](1);
        variant.conditions[0] =
            "admin_ controls setTokenURI and diamondCut through DEFAULT_ADMIN_ROLE; initialization sets no per-token URI";
        result.variants[0] = variant;
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployERC721URIStorage", "run(string,string,address)", variant, "buildCuts(name_,symbol_,admin_)"
        );
    }
}
