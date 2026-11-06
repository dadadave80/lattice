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
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC1155} from "@lattice/tokens/ERC1155/ERC1155.sol";
import {ERC1155Init} from "@lattice/tokens/ERC1155/ERC1155Init.sol";
import {ERC1155URIStorage} from "@lattice/tokens/ERC1155/ERC1155URIStorage.sol";
import {ERC1155URIStorageInit} from "@lattice/tokens/ERC1155/ERC1155URIStorageInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC1155URIStorage
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-1155 diamond with per-token URI storage: `ERC165Facet` + `ERC1155` +
///         `ERC1155URIStorage` + `AccessControl`, seeded by {ERC1155Init} + {ERC1155URIStorageInit} run together
///         in one initializing window via {MultiInit} (see {BaseDeploy._assembleMulti}).
/// @dev Each facet owns ONLY its own selectors (the composability principle): the base `ERC1155` facet exposes the
///      ERC-1155 surface, and `ERC1155URIStorage` is a MIXED cut over it — it REPLACEs `uri(uint256)` (per-token
///      URI storage) and ADDs `setURI`/`setBaseURI`. `AccessControl` is included because both setters are gated
///      on `DEFAULT_ADMIN_ROLE` (bootstrapped by {ERC1155URIStorageInit}), so a production deployment can manage
///      that admin; `AccessControlDiamondCut` lets the same admin upgrade the diamond.
///      All inventory facets and initializers use the shared release helpers.
contract DeployERC1155URIStorage is BaseDeploy {
    /// @notice Builds the URI-storage ERC-1155 diamond cuts + ordered initializers (no broadcast, no proxy).
    /// @param uri_ The ERC-1155 URI template, served for ids without a per-token URI.
    /// @param admin_ The metadata admin (DEFAULT_ADMIN_ROLE).
    /// @return cuts The facet cuts (ERC165 + ERC1155 + ERC1155URIStorage[Add setters, Replace uri] +
    ///         AccessControl + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return inits The initializer contracts ({ERC1155Init}, {ERC1155URIStorageInit}, then
    ///         {DiamondIntrospectionInit.initUpgradeable}), run in order via {MultiInit}.
    /// @return initCalldatas The calldata for each initializer.
    function buildCuts(string memory uri_, address admin_)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));

        inits = new address[](3);
        inits[0] = _init("ERC1155Init");
        inits[1] = _init("ERC1155URIStorageInit");
        inits[2] = _init("DiamondIntrospectionInit");

        initCalldatas = new bytes[](3);
        initCalldatas[0] = abi.encodeCall(ERC1155Init.init, (uri_));
        initCalldatas[1] = abi.encodeCall(ERC1155URIStorageInit.init, (admin_));
        initCalldatas[2] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    /// @notice The `setURI` and `setBaseURI` selectors ADDed by the URI-storage facet.
    function _setters() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = ERC1155URIStorage.setURI.selector;
        s[1] = ERC1155URIStorage.setBaseURI.selector;
    }

    /// @notice The single `uri` selector the URI-storage facet REPLACEs on the base ERC-1155 facet.
    function _uri() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = ERC1155URIStorage.uri.selector;
    }

    function _cutPlan(uint256) internal pure returns (RecipeFacet[] memory facets) {
        facets = new RecipeFacet[](7);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("ERC1155");
        facets[2] = RecipePlanLib.only("ERC1155URIStorage", FacetCutAction.Add, _setters());
        facets[3] = RecipePlanLib.only("ERC1155URIStorage", FacetCutAction.Replace, _uri());
        facets[4] = RecipePlanLib.all("AccessControl");
        facets[5] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[6] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory seams) {
        seams = new RecipeSeam[](1);
        seams[0] = RecipePlanLib.seam2(
            "erc1155-per-token-uri",
            ERC1155URIStorage.uri.selector,
            "ERC1155",
            "ERC1155URIStorage",
            "ERC1155URIStorage",
            "The storage facet must own uri(uint256) so per-token and base URI configuration is honored"
        );
    }

    /// @notice Canonical cut plans, exact nested initialization and authorities as script data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC1155URIStorage", "script/base/tokens/DeployERC1155URIStorage.s.sol", 1);
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployERC1155URIStorage:buildCuts(string,address)";
        variant.buildSignature = "buildCuts(string,address)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Parallel;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](2);
        variant.inputs[0] = RecipeParameter(
            "uri_",
            "string",
            "ERC1155-URI-template",
            "ipfs://example/{id}.json",
            "no nonempty or length constraint; caller supplies the intended metadata template"
        );
        variant.inputs[1] = RecipeParameter(
            "admin_",
            "address",
            "account",
            "0x00000000000000000000000000000000000000ad",
            "caller: choose a usable role and upgrade administrator; initialization permits the zero address"
        );
        RecipeParameter[] memory baseParameters = new RecipeParameter[](1);
        baseParameters[0] = variant.inputs[0];
        string[] memory baseBindings = new string[](1);
        baseBindings[0] = "uri_";
        RecipeInitStep[] memory baseLeaf =
            RecipeSpecLib.leaf("ERC1155Init", "init(string)", baseParameters, baseBindings);
        RecipeInitStep[][] memory children = new RecipeInitStep[][](3);
        children[0] = baseLeaf;
        RecipeParameter[] memory parameters = new RecipeParameter[](1);
        parameters[0] = variant.inputs[1];
        string[] memory bindings = new string[](1);
        bindings[0] = "admin_";
        children[1] = RecipeSpecLib.leaf("ERC1155URIStorageInit", "init(address)", parameters, bindings);
        children[2] = RecipeSpecLib.emptyLeaf("DiamondIntrospectionInit", "initUpgradeable()");
        variant.initPlan = RecipeSpecLib.wrap(children);
        variant.authorities = new RecipeAuthority[](1);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin_",
            "URI setters, role administration and diamondCut"
        );
        variant.conditions = new string[](2);
        variant.conditions[0] =
        "caller: add application mint logic separately; no public mint selector is cut by this recipe";
        variant.conditions[1] =
            "the base URI template is initialized before per-token URI storage; the URI override owns uri(uint256) and both setters";
        result.variants[0] = variant;
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployERC1155URIStorage", "run(string,address)", variant, "buildCuts(uri_,admin_)"
        );
    }

    /// @notice Deploys a URI-storage ERC-1155 token diamond (broadcasting entrypoint for `forge script`).
    /// @return token The deployed token diamond address.
    function run(string memory uri_, address admin_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) = buildCuts(uri_, admin_);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }
}
