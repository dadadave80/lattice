// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
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
import {AccessControlInit} from "@lattice/access/AccessControlInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC1155BurnableInit} from "@lattice/tokens/ERC1155/ERC1155BurnableInit.sol";
import {ERC1155SupplyInit} from "@lattice/tokens/ERC1155/ERC1155SupplyInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC1155Supply
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a supply-tracked, burnable ERC-1155 token diamond: the base {DeployERC1155}
///         recipe (ERC165 + ERC1155 + {ERC1155Init}) plus the {ERC1155Supply} facet, which adds the supply views
///         and the supply-tracking `burn`/`burnBatch`. {ERC1155SupplyInit} registers IERC1155Supply and
///         {ERC1155BurnableInit} registers IERC1155Burnable, since the burns are live. All inits run in one
///         initializing window via {BaseDeploy._assembleMulti}.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut (the inherited base recipe provides the
///      loupe); deploy a new diamond to change behavior. Use the ADMIN overload (`buildCuts(..., admin)` /
///      `run(..., admin)`) for an upgradeable deployment gated on `DEFAULT_ADMIN_ROLE`.
///      Under decision D25(a) on #234, {ERC1155Supply} is mutually exclusive with {ERC1155Burnable} and
///      {ERC1155Pausable}: do not add either here. The recipe cuts no mint; the app's mint facet must call
///      {ERC1155SupplyLib._mint}/{ERC1155SupplyLib._mintBatch}, or the supply falls behind the balances.
///      All inventory facets and initializers use the shared release helpers.
contract DeployERC1155Supply is TokenDeployBase {
    /// @notice Builds the supply-tracked ERC-1155 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param uri_ Token URI template.
    /// @return cuts The facet cuts (ERC165 + ERC1155 + DiamondLoupeFacet + ERC1155Supply).
    /// @return inits The initializers, run in order ({DeployERC1155}'s {MultiInit} chain, {ERC1155SupplyInit},
    ///         then {ERC1155BurnableInit}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory uri_)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (inits, initCalldatas) = _extensionInits(uri_);
    }

    /// @dev Shared typed initializer sequence; callers validate the complete cut plan first.
    function _extensionInits(string memory uri_)
        internal
        returns (address[] memory inits, bytes[] memory initCalldatas)
    {
        (address baseInit, bytes memory baseCalldata) = _erc1155BaseInit(uri_);
        inits = new address[](3);
        inits[0] = baseInit;
        inits[1] = _init("ERC1155SupplyInit");
        inits[2] = _init("ERC1155BurnableInit");

        initCalldatas = new bytes[](3);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC1155SupplyInit.init, ());
        initCalldatas[2] = abi.encodeCall(ERC1155BurnableInit.init, ());
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant < 2, "DeployERC1155Supply: unknown variant");
        RecipeFacet[] memory extension = new RecipeFacet[](variant == 0 ? 1 : 3);
        extension[0] = RecipePlanLib.all("ERC1155Supply");
        if (variant == 1) {
            extension[1] = RecipePlanLib.all("AccessControl");
            extension[2] = RecipePlanLib.all("AccessControlDiamondCut");
        }
        return RecipePlanLib.append(TokenRecipePlans.erc1155(false), extension);
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cut plans, exact nested initialization and authorities as script data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC1155Supply", "script/base/tokens/DeployERC1155Supply.s.sol", 2);
        result.deploymentContexts = new RecipeDeploymentContext[](2);
        for (uint256 i; i < 2; ++i) {
            RecipeVariant memory variant;
            variant.id =
                i == 0 ? "DeployERC1155Supply:buildCuts(string)" : "DeployERC1155Supply:buildCuts(string,address)";
            variant.buildSignature = i == 0 ? "buildCuts(string)" : "buildCuts(string,address)";
            variant.proxyKind = RecipeProxyKind.Lattice;
            variant.initOutputKind = RecipeInitOutputKind.Parallel;
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
            RecipeInitStep[][] memory children = new RecipeInitStep[][](i == 0 ? 3 : 5);
            children[0] = RecipeSpecLib.introspected(baseLeaf, false);
            children[1] = RecipeSpecLib.emptyLeaf("ERC1155SupplyInit", "init()");
            children[2] = RecipeSpecLib.emptyLeaf("ERC1155BurnableInit", "init()");
            if (i == 1) {
                RecipeParameter[] memory parameters = new RecipeParameter[](1);
                parameters[0] = variant.inputs[1];
                string[] memory bindings = new string[](1);
                bindings[0] = "admin";
                children[3] = RecipeSpecLib.leaf("AccessControlInit", "init(address)", parameters, bindings);
                children[4] = RecipeSpecLib.emptyLeaf("DiamondIntrospectionInit", "initUpgradeable()");
            }
            variant.initPlan = RecipeSpecLib.wrap(children);
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
            variant.conditions = new string[](4);
            variant.conditions[0] =
            "caller: add application mint logic separately; no public mint selector is cut by this recipe";
            variant.conditions[1] =
                "caller: initialize before any token balances exist; the initializer does not reconstruct per-id or aggregate supply";
            variant.conditions[2] =
                "caller: mint through ERC1155SupplyLib._mint/_mintBatch to keep supplies synchronized; do not co-cut ERC1155Burnable or ERC1155Pausable";
            variant.conditions[3] =
                "ERC1155BurnableInit registers the burn interface, but the burn routes belong to ERC1155Supply; no ERC1155Burnable facet is cut";
            result.variants[i] = variant;
            result.deploymentContexts[i] = RecipeSpecLib.deploymentContext(
                "DeployERC1155Supply",
                i == 0 ? "run(string)" : "run(string,address)",
                variant,
                i == 0 ? "buildCuts(uri_)" : "buildCuts(uri_,admin)"
            );
        }
    }

    /// @notice Deploys a supply-tracked ERC-1155 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(string memory uri_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) = buildCuts(uri_);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(string memory uri_, address admin)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        cuts = _materialize(_cutPlan(1), _recipeSeams(1));
        (address[] memory defInits, bytes[] memory defCalldatas) = _extensionInits(uri_);

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
    function run(string memory uri_, address admin) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) = buildCuts(uri_, admin);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }
}
