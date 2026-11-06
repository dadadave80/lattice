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

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {TokenDeployBase} from "@lattice-script/base/tokens/TokenDeployBase.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {ERC20Pausable} from "@lattice/tokens/ERC20/ERC20Pausable.sol";
import {ERC20PausableInit} from "@lattice/tokens/ERC20/ERC20PausableInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC20Pausable
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a pausable ERC-20 token diamond: the base {DeployERC20} recipe
///         (ERC165 + ERC20 + {ERC20Init}), the {Pausable} facet (admin-gated `pause()`/`unpause()`), and the
///         {ERC20Pausable} facet which REPLACES the base `transfer`/`transferFrom` with pause-gated variants.
///         {ERC20PausableInit} registers IPausable (ERC-165) and grants `admin` the DEFAULT_ADMIN_ROLE. Both
///         inits run in one initializing window via {BaseDeploy._assembleMulti}.
contract DeployERC20Pausable is TokenDeployBase {
    /// @notice Builds the pausable ERC-20 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name. @param symbol_ Token symbol. @param admin The pause/unpause authority.
    /// @return cuts The facet cuts (ERC165 + ERC20 + DiamondLoupeFacet [base] + Pausable [Add] + ERC20Pausable [Replace] + AccessControl + AccessControlDiamondCut).
    /// @return inits The initializers, run in order ({DeployERC20}'s {MultiInit} chain, {ERC20PausableInit}, then {DiamondIntrospectionInit.initUpgradeable}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory name_, string memory symbol_, address admin)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (address baseInit, bytes memory baseCalldata) = _erc20BaseInit(name_, symbol_);

        inits = new address[](3);
        inits[0] = baseInit;
        inits[1] = _init("ERC20PausableInit");
        inits[2] = _init("DiamondIntrospectionInit");

        initCalldatas = new bytes[](3);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC20PausableInit.init, (admin));
        // The base chain registered the loupe flag; the cut facet is live too — advertise both.
        initCalldatas[2] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    function _cutPlan(uint256 variant) internal pure virtual returns (RecipeFacet[] memory) {
        require(variant == 0, "DeployERC20Pausable: unknown variant");
        RecipeFacet[] memory extension = new RecipeFacet[](4);
        extension[0] = RecipePlanLib.all("Pausable");
        extension[1] = RecipePlanLib.replaceAll("ERC20Pausable");
        extension[2] = RecipePlanLib.all("AccessControl");
        extension[3] = RecipePlanLib.all("AccessControlDiamondCut");
        return RecipePlanLib.append(TokenRecipePlans.erc20(false), extension);
    }

    function _recipeSeams(uint256) internal pure virtual returns (RecipeSeam[] memory seams) {
        seams = new RecipeSeam[](2);
        seams[0] = RecipePlanLib.seam2(
            "ERC20Pausable.transfer(address,uint256)",
            bytes4(keccak256("transfer(address,uint256)")),
            "ERC20",
            "ERC20Pausable",
            "ERC20Pausable",
            "pause-gated movement"
        );
        seams[1] = RecipePlanLib.seam2(
            "ERC20Pausable.transferFrom(address,address,uint256)",
            bytes4(keccak256("transferFrom(address,address,uint256)")),
            "ERC20",
            "ERC20Pausable",
            "ERC20Pausable",
            "pause-gated movement"
        );
    }

    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC20Pausable", "script/base/tokens/DeployERC20Pausable.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployERC20Pausable:buildCuts(string,string,address)";
        variant.buildSignature = "buildCuts(string,string,address)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Parallel;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](3);
        variant.inputs[0] = RecipeParameter("name_", "string", "metadata", "Example Token", "no length constraint");
        variant.inputs[1] = RecipeParameter("symbol_", "string", "metadata", "EXM", "no length constraint");
        variant.inputs[2] = RecipeSpecLib.aclAdministrator("admin");
        RecipeInitStep[][] memory children = new RecipeInitStep[][](3);
        children[0] = RecipeSpecLib.tokenBase("ERC20Init", "name_", "symbol_");
        RecipeParameter[] memory parameters = new RecipeParameter[](1);
        parameters[0] = RecipeSpecLib.aclAdministrator("admin_");
        string[] memory bindings = new string[](1);
        bindings[0] = "admin";
        children[1] = RecipeSpecLib.leaf("ERC20PausableInit", "init(address)", parameters, bindings);
        children[2] = RecipeSpecLib.emptyLeaf("DiamondIntrospectionInit", "initUpgradeable()");
        variant.initPlan = RecipeSpecLib.wrap(children);
        variant.authorities = new RecipeAuthority[](1);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl", "DEFAULT_ADMIN_ROLE", "bytes32", bytes32(0), "admin", "pause management and diamondCut"
        );
        variant.conditions = new string[](1);
        variant.conditions[0] =
        "Checked script rejects ERC1363; other token movement combinations require the reviewed ADR0009 policy";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployERC20Pausable", "run(string,string,address)", variant, "buildCuts(name_,symbol_,admin)"
        );
    }

    /// @notice Deploys a pausable ERC-20 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(string memory name_, string memory symbol_, address admin) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, admin);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }
}
