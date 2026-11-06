// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {TokenDeployBase} from "@lattice-script/base/tokens/TokenDeployBase.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlInit} from "@lattice/access/AccessControlInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC20Wrapper} from "@lattice/tokens/ERC20/ERC20Wrapper.sol";
import {ERC20WrapperInit} from "@lattice/tokens/ERC20/ERC20WrapperInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC20Wrapper
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a wrapper ERC-20 token diamond that wraps an existing `underlying_` ERC-20
///         1:1: the base {DeployERC20} recipe (ERC165 + ERC20 + {ERC20Init}) plus the {ERC20Wrapper} facet. The
///         wrapper facet is a MIXED cut — its `decimals()` REPLACES the base ERC-20 `decimals()` (to mirror the
///         underlying), while `underlying`/`depositFor`/`withdrawTo` are ADDED. {ERC20WrapperInit} records the
///         underlying. Both inits run in one initializing window via {BaseDeploy._assembleMulti}.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut (the inherited base recipe provides the
///      loupe); deploy a new diamond to change behavior. Use the ADMIN overload (`buildCuts(..., admin)` /
///      `run(..., admin)`) for an upgradeable deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployERC20Wrapper is TokenDeployBase {
    /// @notice Builds the wrapper ERC-20 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name. @param symbol_ Token symbol. @param underlying_ The wrapped ERC-20 token.
    /// @return cuts The facet cuts (ERC165 + ERC20 + ERC20Wrapper[Replace decimals] + ERC20Wrapper[Add rest]).
    /// @return inits The initializers, run in order ({DeployERC20}'s {MultiInit} chain, then {ERC20WrapperInit}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory name_, string memory symbol_, address underlying_)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (inits, initCalldatas) = _buildInitializers(name_, symbol_, underlying_);
    }

    /// @notice Deploys a wrapper ERC-20 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(string memory name_, string memory symbol_, address underlying_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, underlying_);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(string memory name_, string memory symbol_, address underlying_, address admin)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        cuts = _materialize(_cutPlan(1), _recipeSeams(1));
        (address[] memory defInits, bytes[] memory defCalldatas) = _buildInitializers(name_, symbol_, underlying_);

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
    function run(string memory name_, string memory symbol_, address underlying_, address admin)
        external
        returns (address token)
    {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, underlying_, admin);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }

    function _buildInitializers(string memory name_, string memory symbol_, address underlying_)
        internal
        returns (address[] memory inits, bytes[] memory initCalldatas)
    {
        (address baseInit, bytes memory baseCalldata) = _erc20BaseInit(name_, symbol_);
        inits = new address[](2);
        inits[0] = baseInit;
        inits[1] = _init("ERC20WrapperInit");

        initCalldatas = new bytes[](2);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC20WrapperInit.init, (underlying_));
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory cuts) {
        require(variant < 2, "DeployERC20Wrapper: unknown variant");
        RecipeFacet[] memory extension = new RecipeFacet[](variant == 0 ? 2 : 4);
        bytes4[] memory added = new bytes4[](3);
        added[0] = ERC20Wrapper.underlying.selector;
        added[1] = ERC20Wrapper.depositFor.selector;
        added[2] = ERC20Wrapper.withdrawTo.selector;
        bytes4[] memory replaced = new bytes4[](1);
        replaced[0] = ERC20Wrapper.decimals.selector;
        extension[0] = RecipePlanLib.only("ERC20Wrapper", FacetCutAction.Add, added);
        extension[1] = RecipePlanLib.only("ERC20Wrapper", FacetCutAction.Replace, replaced);
        if (variant == 1) {
            extension[2] = RecipePlanLib.all("AccessControl");
            extension[3] = RecipePlanLib.all("AccessControlDiamondCut");
        }
        return RecipePlanLib.append(TokenRecipePlans.erc20(false), extension);
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory seams) {
        seams = new RecipeSeam[](1);
        seams[0] = RecipePlanLib.seam2(
            "underlying-decimals",
            ERC20Wrapper.decimals.selector,
            "ERC20",
            "ERC20Wrapper",
            "ERC20Wrapper",
            "wrapper decimals mirror the cached underlying decimals"
        );
    }

    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC20Wrapper", "script/base/tokens/DeployERC20Wrapper.s.sol", 2);
        result.deploymentContexts = new RecipeDeploymentContext[](2);
        for (uint256 i; i < 2; ++i) {
            RecipeVariant memory variant;
            variant.buildSignature =
                i == 0 ? "buildCuts(string,string,address)" : "buildCuts(string,string,address,address)";
            variant.id = string.concat("DeployERC20Wrapper:", variant.buildSignature);
            variant.proxyKind = RecipeProxyKind.Lattice;
            variant.initOutputKind = RecipeInitOutputKind.Parallel;
            variant.facets = _cutPlan(i);
            variant.seams = _recipeSeams(i);
            variant.inputs = new RecipeParameter[](i == 0 ? 3 : 4);
            variant.inputs[0] = RecipeParameter("name_", "string", "metadata", "Wrapped Token", "no length constraint");
            variant.inputs[1] = RecipeParameter("symbol_", "string", "metadata", "WEXM", "no length constraint");
            variant.inputs[2] = RecipeParameter(
                "underlying_",
                "address",
                "ERC20-contract",
                "target-configured-underlying",
                "enforced: not diamond-self; caller authenticates usable underlying; zero/code not rejected and decimals default18 after failed reads"
            );
            RecipeParameter[] memory parameters = new RecipeParameter[](1);
            parameters[0] = variant.inputs[2];
            string[] memory bindings = new string[](1);
            bindings[0] = "underlying_";
            RecipeInitStep[][] memory children = new RecipeInitStep[][](i == 0 ? 2 : 4);
            children[0] = RecipeSpecLib.tokenBase("ERC20Init", "name_", "symbol_");
            children[1] = RecipeSpecLib.leaf("ERC20WrapperInit", "init(address)", parameters, bindings);
            if (i == 0) {
                variant.authorities = new RecipeAuthority[](0);
            } else {
                variant.inputs[3] = RecipeSpecLib.aclAdministrator("admin");
                RecipeParameter[] memory adminParameters = new RecipeParameter[](1);
                adminParameters[0] = RecipeSpecLib.aclAdministrator("admin");
                string[] memory adminBindings = new string[](1);
                adminBindings[0] = "admin";
                children[2] = RecipeSpecLib.leaf("AccessControlInit", "init(address)", adminParameters, adminBindings);
                children[3] = RecipeSpecLib.emptyLeaf("DiamondIntrospectionInit", "initUpgradeable()");
                variant.authorities = new RecipeAuthority[](1);
                variant.authorities[0] = RecipeSpecLib.role(
                    "AccessControl",
                    "DEFAULT_ADMIN_ROLE",
                    "bytes32",
                    bytes32(0),
                    "admin",
                    "diamondCut and role administration"
                );
            }
            variant.initPlan = RecipeSpecLib.wrap(children);
            variant.conditions = new string[](1);
            variant.conditions[0] =
                "Wrapping is1:1 in raw underlying units; callers authenticate token transfer behavior and account for fee/rebase risks";
            result.variants[i] = variant;
            result.deploymentContexts[i] = RecipeSpecLib.deploymentContext(
                "DeployERC20Wrapper",
                i == 0 ? "run(string,string,address)" : "run(string,string,address,address)",
                variant,
                i == 0 ? "buildCuts(name_,symbol_,underlying_)" : "buildCuts(name_,symbol_,underlying_,admin)"
            );
        }
    }
}
