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
import {TokenRecipePlans} from "@lattice-script/lib/TokenRecipePlans.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC2981} from "@lattice/tokens/ERC2981/ERC2981.sol";
import {ERC2981Init} from "@lattice/tokens/ERC2981/ERC2981Init.sol";
import {ERC721} from "@lattice/tokens/ERC721/ERC721.sol";
import {ERC721Init} from "@lattice/tokens/ERC721/ERC721Init.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC721Royalty
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-721 token with ERC-2981 royalties (the OpenZeppelin `ERC721Royalty`
///         equivalent): `ERC165Facet` + `ERC721` + `ERC2981` + `AccessControl`, seeded by {ERC721Init} and
///         {ERC2981Init} in one initializing window via {MultiInit} (see {BaseDeploy._assembleMulti}).
/// @dev OpenZeppelin v5.6.1's `ERC721Royalty` only merges `supportsInterface`, which the shared ERC-165 map does
///      here, and v5 no longer clears royalties on burn, so the two facets need no seam: every selector is
///      ADDed. `AccessControl` is included because every royalty setter is gated on `DEFAULT_ADMIN_ROLE`, which
///      {ERC2981Init} grants to `admin_`; `AccessControlDiamondCut` lets that admin upgrade the diamond, as in
///      {DeployERC2981} and {DeployERC721URIStorage}.
contract DeployERC721Royalty is BaseDeploy {
    /// @notice Builds the royalty ERC-721 diamond cuts + ordered initializers (no broadcast, no proxy).
    /// @param name_ Token name. @param symbol_ Token symbol. @param admin_ The royalty admin (DEFAULT_ADMIN_ROLE).
    /// @return cuts The facet cuts (ERC165 + ERC721 + ERC2981 + AccessControl + DiamondLoupeFacet +
    ///         AccessControlDiamondCut).
    /// @return inits The initializer contracts ({ERC721Init}, {ERC2981Init}, then
    ///         {DiamondIntrospectionInit.initUpgradeable}), run in order via {MultiInit}.
    /// @return initCalldatas The calldata for each initializer.
    function buildCuts(string memory name_, string memory symbol_, address admin_)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));

        inits = new address[](3);
        inits[0] = _init("ERC721Init");
        inits[1] = _init("ERC2981Init");
        inits[2] = _init("DiamondIntrospectionInit");

        initCalldatas = new bytes[](3);
        initCalldatas[0] = abi.encodeCall(ERC721Init.init, (name_, symbol_));
        initCalldatas[1] = abi.encodeCall(ERC2981Init.init, (admin_));
        initCalldatas[2] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    /// @notice Deploys a royalty ERC-721 token diamond (broadcasting entrypoint for `forge script`).
    /// @return token The deployed token diamond address.
    function run(string memory name_, string memory symbol_, address admin_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, admin_);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployERC721Royalty: unknown variant");
        RecipeFacet[] memory base = TokenRecipePlans.erc721(false);
        facets = new RecipeFacet[](6);
        facets[0] = base[0];
        facets[1] = base[1];
        facets[2] = RecipePlanLib.all("ERC2981");
        facets[3] = RecipePlanLib.all("AccessControl");
        facets[4] = base[2];
        facets[5] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory seams) {
        seams = new RecipeSeam[](0);
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
            moduleParameters[0] = RecipeParameter("admin", "address", inputs[2].unit, inputs[2].example, inputs[2].rule);
            moduleBindings[0] = "admin_";
            module = RecipeSpecLib.leaf("ERC2981Init", "init(address)", moduleParameters, moduleBindings);
        }
        RecipeInitStep[][] memory children = new RecipeInitStep[][](3);
        children[0] = baseModule;
        children[1] = module;
        children[2] = RecipeSpecLib.emptyLeaf("DiamondIntrospectionInit", "initUpgradeable()");
        return RecipeSpecLib.wrap(children);
    }

    /// @notice Canonical cut/seam plans, exact initializer tree and deployment arguments as script-only data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC721Royalty", "script/base/tokens/DeployERC721Royalty.s.sol", 1);
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployERC721Royalty:buildCuts(string,string,address)";
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
            "royalty configuration, role administration and diamondCut"
        );
        variant.conditions = new string[](2);
        variant.conditions[0] =
            "the only variant is admin-upgradeable; ERC2981Init grants admin_ DEFAULT_ADMIN_ROLE for royalty configuration and diamondCut";
        variant.conditions[1] =
            "royalty recipients and fee rates are configured after deployment, not initialized by this builder; royalties are not automatically cleared on burn";
        result.variants[0] = variant;
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployERC721Royalty", "run(string,string,address)", variant, "buildCuts(name_,symbol_,admin_)"
        );
    }
}
