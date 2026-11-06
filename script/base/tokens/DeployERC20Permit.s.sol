// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
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
import {ERC20Permit} from "@lattice/tokens/ERC20/ERC20Permit.sol";
import {ERC20PermitInit} from "@lattice/tokens/ERC20/ERC20PermitInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC20Permit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a permit-enabled ERC-20 token diamond: the base {DeployERC20} recipe
///         (ERC165 + ERC20 + {ERC20Init}) plus the additive {ERC20Permit} facet (ERC-2612
///         `permit`/`nonces`/`DOMAIN_SEPARATOR`) and its {ERC20PermitInit} which seeds the EIP-712 domain + nonce
///         storage the permit digest reads. `buildCuts` is the broadcast-free primitive the permit facet test
///         reuses; `run` broadcasts. Both inits run in one initializing window via {BaseDeploy._assembleMulti}.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut (the inherited base recipe provides the
///      loupe); deploy a new diamond to change behavior. Use the ADMIN overload (`buildCuts(..., admin)` /
///      `run(..., admin)`) for an upgradeable deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployERC20Permit is TokenDeployBase {
    /// @notice Builds the permit ERC-20 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name (also the EIP-712 domain name). @param symbol_ Token symbol.
    /// @return cuts The facet cuts (ERC165 + ERC20 + ERC20Permit).
    /// @return inits The initializers, run in order ({DeployERC20}'s {MultiInit} chain, then {ERC20PermitInit}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory name_, string memory symbol_)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (inits, initCalldatas) = _extensionInits(name_, symbol_);
    }

    /// @dev Preserve typed init order while each caller validates its complete cut plan first.
    function _extensionInits(string memory name_, string memory symbol_)
        internal
        returns (address[] memory inits, bytes[] memory initCalldatas)
    {
        (address baseInit, bytes memory baseCalldata) = _erc20BaseInit(name_, symbol_);
        inits = new address[](2);
        inits[0] = baseInit;
        inits[1] = _init("ERC20PermitInit");

        initCalldatas = new bytes[](2);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC20PermitInit.init, (name_));
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant < 2, "DeployERC20Permit: unknown variant");
        RecipeFacet[] memory extension = new RecipeFacet[](variant == 0 ? 1 : 3);
        extension[0] = RecipePlanLib.all("ERC20Permit");
        if (variant == 1) {
            extension[1] = RecipePlanLib.all("AccessControl");
            extension[2] = RecipePlanLib.all("AccessControlDiamondCut");
        }
        return RecipePlanLib.append(TokenRecipePlans.erc20(false), extension);
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Both canonical variants with exact nested initialization and source-backed constraints.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC20Permit", "script/base/tokens/DeployERC20Permit.s.sol", 2);
        result.deploymentContexts = new RecipeDeploymentContext[](2);
        for (uint256 i; i < 2; ++i) {
            RecipeVariant memory variant;
            variant.id = i == 0
                ? "DeployERC20Permit:buildCuts(string,string)"
                : "DeployERC20Permit:buildCuts(string,string,address)";
            variant.buildSignature = i == 0 ? "buildCuts(string,string)" : "buildCuts(string,string,address)";
            variant.proxyKind = RecipeProxyKind.Lattice;
            variant.initOutputKind = RecipeInitOutputKind.Parallel;
            variant.facets = _cutPlan(i);
            variant.seams = _recipeSeams(i);
            variant.inputs = new RecipeParameter[](i == 0 ? 2 : 3);
            variant.inputs[0] = RecipeParameter(
                "name_",
                "string",
                "metadata",
                "Example Token",
                "enforced: nonempty EIP712 domain name; no upper length constraint"
            );
            variant.inputs[1] = RecipeParameter("symbol_", "string", "metadata", "EXM", "no length constraint");
            if (i == 1) variant.inputs[2] = RecipeSpecLib.aclAdministrator("admin");
            RecipeInitStep[][] memory children = new RecipeInitStep[][](i == 0 ? 2 : 4);
            children[0] = RecipeSpecLib.tokenBase("ERC20Init", "name_", "symbol_");
            RecipeParameter[] memory extensionParameters = new RecipeParameter[](1);
            extensionParameters[0] = variant.inputs[0];
            string[] memory extensionBindings = new string[](1);
            extensionBindings[0] = "name_";
            children[1] = RecipeSpecLib.leaf("ERC20PermitInit", "init(string)", extensionParameters, extensionBindings);
            if (i == 1) {
                RecipeParameter[] memory parameters = new RecipeParameter[](1);
                parameters[0] = variant.inputs[2];
                string[] memory bindings = new string[](1);
                bindings[0] = "admin";
                children[2] = RecipeSpecLib.leaf("AccessControlInit", "init(address)", parameters, bindings);
                children[3] = RecipeSpecLib.emptyLeaf("DiamondIntrospectionInit", "initUpgradeable()");
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
                    "role administration and diamondCut; this recipe grants no token minting role"
                );
            }
            variant.conditions = new string[](3);
            variant.conditions[0] =
                "caller: implement ordinary persistent token issuance in application facets; this recipe provides no ordinary mint endpoint";
            variant.conditions[1] =
                "the permit bundle uses token name_ for EIP712 and version 1, then initializes Nonces and registers ERC20Permit";
            variant.conditions[2] =
                "caller: preserve any existing EIP712 identity and use a separately reviewed migration for legacy domain state";
            result.variants[i] = variant;
            result.deploymentContexts[i] = RecipeSpecLib.deploymentContext(
                "DeployERC20Permit",
                i == 0 ? "run(string,string)" : "run(string,string,address)",
                variant,
                i == 0 ? "buildCuts(name_,symbol_)" : "buildCuts(name_,symbol_,admin)"
            );
        }
    }

    /// @notice Deploys a permit ERC-20 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
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
        (address[] memory defInits, bytes[] memory defCalldatas) = _extensionInits(name_, symbol_);

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
}
