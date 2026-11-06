// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC1155} from "@lattice-script/base/tokens/DeployERC1155.s.sol";
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
import {ERC1155BurnableInit} from "@lattice/tokens/ERC1155/ERC1155BurnableInit.sol";
import {ERC1155Pausable} from "@lattice/tokens/ERC1155/ERC1155Pausable.sol";
import {ERC1155PausableInit} from "@lattice/tokens/ERC1155/ERC1155PausableInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC1155Pausable
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a pausable, burnable ERC-1155 token diamond: the base {DeployERC1155} recipe
///         (ERC165 + ERC1155 + {ERC1155Init}), the {Pausable} facet (admin-gated `pause()`/`unpause()`), and the
///         {ERC1155Pausable} facet as a mixed cut — it REPLACES the base `safeTransferFrom`/`safeBatchTransferFrom`
///         with pause-gated variants and ADDS pause-gated `burn`/`burnBatch`. {ERC1155PausableInit} registers
///         IPausable and grants `admin` the DEFAULT_ADMIN_ROLE; {ERC1155BurnableInit} registers IERC1155Burnable,
///         since the burns are live. All inits run in one initializing window via {BaseDeploy._assembleMulti}.
/// @dev Upgradeable: `AccessControl` makes the pause authority inspectable and rotatable, and
///      `AccessControlDiamondCut` lets the same admin `diamondCut`. Under decision D25(a) on #234,
///      {ERC1155Pausable} is mutually exclusive with {ERC1155Burnable} and {ERC1155Supply}: do not add either here.
///      The recipe cuts no mint; the app's mint facet must call {ERC1155PausableLib._mint}/
///      {ERC1155PausableLib._mintBatch}, or mints ignore the pause.
///      All inventory facets and initializers use the shared release helpers.
contract DeployERC1155Pausable is TokenDeployBase {
    /// @notice Builds the pausable ERC-1155 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param uri_ Token URI template. @param admin The pause/unpause and upgrade authority.
    /// @return cuts The facet cuts (ERC165 + ERC1155 + DiamondLoupeFacet [base] + Pausable [Add] +
    ///         ERC1155Pausable [Replace transfers, Add burns] + AccessControl + AccessControlDiamondCut).
    /// @return inits The initializers, run in order ({DeployERC1155}'s {MultiInit} chain, {ERC1155PausableInit},
    ///         {ERC1155BurnableInit}, then {DiamondIntrospectionInit.initUpgradeable}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory uri_, address admin)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (address baseInit, bytes memory baseCalldata) = _erc1155BaseInit(uri_);

        inits = new address[](4);
        inits[0] = baseInit;
        inits[1] = _init("ERC1155PausableInit");
        inits[2] = _init("ERC1155BurnableInit");
        inits[3] = _init("DiamondIntrospectionInit");

        initCalldatas = new bytes[](4);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC1155PausableInit.init, (admin));
        initCalldatas[2] = abi.encodeCall(ERC1155BurnableInit.init, ());
        // The base chain registered the loupe flag; the cut facet is live too — advertise both.
        initCalldatas[3] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    /// @notice The `safeTransferFrom`/`safeBatchTransferFrom` selectors the pausable facet REPLACEs on the base.
    function _transfers() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = ERC1155Pausable.safeTransferFrom.selector;
        s[1] = ERC1155Pausable.safeBatchTransferFrom.selector;
    }

    /// @notice The `burn`/`burnBatch` selectors the pausable facet ADDs.
    function _burns() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = ERC1155Pausable.burn.selector;
        s[1] = ERC1155Pausable.burnBatch.selector;
    }

    function _cutPlan(uint256) internal pure returns (RecipeFacet[] memory facets) {
        RecipeFacet[] memory extension = new RecipeFacet[](5);
        extension[0] = RecipePlanLib.all("Pausable");
        extension[1] = RecipePlanLib.only("ERC1155Pausable", FacetCutAction.Replace, _transfers());
        extension[2] = RecipePlanLib.only("ERC1155Pausable", FacetCutAction.Add, _burns());
        extension[3] = RecipePlanLib.all("AccessControl");
        extension[4] = RecipePlanLib.all("AccessControlDiamondCut");
        return RecipePlanLib.append(TokenRecipePlans.erc1155(false), extension);
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory seams) {
        bytes4[] memory selectors = _transfers();
        seams = new RecipeSeam[](2);
        for (uint256 i; i < 2; ++i) {
            seams[i] = RecipePlanLib.seam2(
                i == 0 ? "erc1155-pausable-single-transfer" : "erc1155-pausable-batch-transfer",
                selectors[i],
                "ERC1155",
                "ERC1155Pausable",
                "ERC1155Pausable",
                "The pausable facet must own both transfer routes so transfers cannot bypass the pause gate"
            );
        }
    }

    /// @notice Canonical cut plans, exact nested initialization and authorities as script data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC1155Pausable", "script/base/tokens/DeployERC1155Pausable.s.sol", 1);
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployERC1155Pausable:buildCuts(string,address)";
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
            "admin",
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
        RecipeInitStep[][] memory children = new RecipeInitStep[][](4);
        children[0] = RecipeSpecLib.introspected(baseLeaf, false);
        RecipeParameter[] memory parameters = new RecipeParameter[](1);
        parameters[0] = RecipeParameter(
            "admin_",
            "address",
            "account",
            "0x00000000000000000000000000000000000000ad",
            "caller: choose a usable role and upgrade administrator; initialization permits the zero address"
        );
        string[] memory bindings = new string[](1);
        bindings[0] = "admin";
        children[1] = RecipeSpecLib.leaf("ERC1155PausableInit", "init(address)", parameters, bindings);
        children[2] = RecipeSpecLib.emptyLeaf("ERC1155BurnableInit", "init()");
        children[3] = RecipeSpecLib.emptyLeaf("DiamondIntrospectionInit", "initUpgradeable()");
        variant.initPlan = RecipeSpecLib.wrap(children);
        variant.authorities = new RecipeAuthority[](1);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "pause/unpause, role administration and diamondCut"
        );
        variant.conditions = new string[](3);
        variant.conditions[0] =
        "caller: add application mint logic separately; no public mint selector is cut by this recipe";
        variant.conditions[1] =
            "caller: mint through ERC1155PausableLib._mint/_mintBatch to enforce pause; do not co-cut ERC1155Burnable or ERC1155Supply";
        variant.conditions[2] =
            "the mixed cut replaces both transfers and adds both burns; only the transfer pair requires ownership seams";
        result.variants[0] = variant;
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployERC1155Pausable", "run(string,address)", variant, "buildCuts(uri_,admin)"
        );
    }

    /// @notice Deploys a pausable ERC-1155 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(string memory uri_, address admin) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) = buildCuts(uri_, admin);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }
}
