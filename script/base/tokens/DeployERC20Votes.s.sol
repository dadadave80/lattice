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
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {Votes} from "@lattice/governance/Votes.sol";
import {ERC20Votes} from "@lattice/tokens/ERC20/ERC20Votes.sol";
import {ERC20VotesInit} from "@lattice/tokens/ERC20/ERC20VotesInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC20Votes
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a governance ERC-20 (ERC-5805 votes) token diamond: the base {DeployERC20}
///         recipe (ERC165 + ERC20 + {ERC20Init}), the {Votes} facet (ERC-5805 delegation + ERC-6372 clock), the
///         {ERC20Votes} facet, and the {AccessControl} facet whose DEFAULT_ADMIN_ROLE gates a consumer's minting
///         authority. Each facet owns ONLY its own selectors (the composability principle): the {Votes} facet
///         ADDs `getVotes`/`getPastVotes`/`getPastTotalSupply`/`delegates`/`delegate`/`delegateBySig`/`clock`/
///         `CLOCK_MODE`; {ERC20Votes} is a MIXED cut — its checkpoint-updating `transfer`/`transferFrom` REPLACE
///         the base ERC-20 variants and its balance-aware `delegate`/`delegateBySig` REPLACE the base {Votes}
///         variants (so vote weight moves with balances), while `numCheckpoints`/`checkpoints` are ADDED.
///         {ERC20VotesInit} seeds the EIP-712 domain, nonce, checkpoint, and role state. Both inits run in one
///         initializing window via {BaseDeploy._assembleMulti}.
contract DeployERC20Votes is TokenDeployBase {
    /// @notice Builds the votes ERC-20 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name (also the EIP-712 domain name). @param symbol_ Token symbol.
    /// @param admin The address granted DEFAULT_ADMIN_ROLE.
    /// @return cuts The facet cuts (ERC165 + ERC20 + DiamondLoupeFacet [base] + Votes + ERC20Votes[Add
    ///         checkpoints, Replace transfer/transferFrom/delegate/delegateBySig] + AccessControl +
    ///         AccessControlDiamondCut).
    /// @return inits The initializers, run in order ({ERC20Init} chain, {ERC20VotesInit}, then
    ///         {DiamondIntrospectionInit.initUpgradeable}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory name_, string memory symbol_, address admin)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (address baseInit, bytes memory baseCalldata) = _erc20BaseInit(name_, symbol_);

        inits = new address[](3);
        inits[0] = baseInit;
        inits[1] = _init("ERC20VotesInit");
        inits[2] = _init("DiamondIntrospectionInit");

        initCalldatas = new bytes[](3);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC20VotesInit.init, (name_, admin));
        // The base chain registered the loupe flag; the cut facet is live too — advertise both.
        initCalldatas[2] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    function _cutPlan(uint256 variant) internal pure virtual returns (RecipeFacet[] memory) {
        require(variant == 0, "DeployERC20Votes: unknown variant");
        bytes4[] memory replaceSelectors = new bytes4[](4);
        replaceSelectors[0] = ERC20Votes.transfer.selector;
        replaceSelectors[1] = ERC20Votes.transferFrom.selector;
        replaceSelectors[2] = ERC20Votes.delegate.selector;
        replaceSelectors[3] = ERC20Votes.delegateBySig.selector;
        bytes4[] memory addSelectors = new bytes4[](2);
        addSelectors[0] = ERC20Votes.numCheckpoints.selector;
        addSelectors[1] = ERC20Votes.checkpoints.selector;
        RecipeFacet[] memory extension = new RecipeFacet[](5);
        extension[0] = RecipePlanLib.all("Votes");
        extension[1] = RecipePlanLib.only("ERC20Votes", FacetCutAction.Add, addSelectors);
        extension[2] = RecipePlanLib.only("ERC20Votes", FacetCutAction.Replace, replaceSelectors);
        extension[3] = RecipePlanLib.all("AccessControl");
        extension[4] = RecipePlanLib.all("AccessControlDiamondCut");
        return RecipePlanLib.append(TokenRecipePlans.erc20(false), extension);
    }

    function _recipeSeams(uint256) internal pure virtual returns (RecipeSeam[] memory seams) {
        seams = new RecipeSeam[](4);
        seams[0] = RecipePlanLib.seam2(
            "ERC20Votes.transfer(address,uint256)",
            bytes4(keccak256("transfer(address,uint256)")),
            "ERC20",
            "ERC20Votes",
            "ERC20Votes",
            "checkpointed balance movement"
        );
        seams[1] = RecipePlanLib.seam2(
            "ERC20Votes.transferFrom(address,address,uint256)",
            bytes4(keccak256("transferFrom(address,address,uint256)")),
            "ERC20",
            "ERC20Votes",
            "ERC20Votes",
            "checkpointed balance movement"
        );
        seams[2] = RecipePlanLib.seam2(
            "ERC20Votes.delegate(address)",
            bytes4(keccak256("delegate(address)")),
            "Votes",
            "ERC20Votes",
            "ERC20Votes",
            "balance-aware delegation"
        );
        seams[3] = RecipePlanLib.seam2(
            "ERC20Votes.delegateBySig(address,uint256,uint256,uint8,bytes32,bytes32)",
            bytes4(keccak256("delegateBySig(address,uint256,uint256,uint8,bytes32,bytes32)")),
            "Votes",
            "ERC20Votes",
            "ERC20Votes",
            "balance-aware delegation"
        );
    }

    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC20Votes", "script/base/tokens/DeployERC20Votes.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployERC20Votes:buildCuts(string,string,address)";
        variant.buildSignature = "buildCuts(string,string,address)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Parallel;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](3);
        variant.inputs[0] =
            RecipeParameter("name_", "string", "metadata", "Example Token", "enforced: nonempty EIP712 domain name");
        variant.inputs[1] = RecipeParameter("symbol_", "string", "metadata", "EXM", "no length constraint");
        variant.inputs[2] = RecipeSpecLib.aclAdministrator("admin");
        RecipeInitStep[][] memory children = new RecipeInitStep[][](3);
        children[0] = RecipeSpecLib.tokenBase("ERC20Init", "name_", "symbol_");
        RecipeParameter[] memory parameters = new RecipeParameter[](2);
        parameters[0] = variant.inputs[0];
        parameters[1] = RecipeSpecLib.aclAdministrator("admin_");
        string[] memory bindings = new string[](2);
        bindings[0] = "name_";
        bindings[1] = "admin";
        children[1] = RecipeSpecLib.leaf("ERC20VotesInit", "init(string,address)", parameters, bindings);
        children[2] = RecipeSpecLib.emptyLeaf("DiamondIntrospectionInit", "initUpgradeable()");
        variant.initPlan = RecipeSpecLib.wrap(children);
        variant.authorities = new RecipeAuthority[](1);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl", "DEFAULT_ADMIN_ROLE", "bytes32", bytes32(0), "admin", "role management and diamondCut"
        );
        variant.conditions = new string[](2);
        variant.conditions[0] =
        "Checked script rejects ERC1363; other token movement combinations require the reviewed ADR0009 policy";
        variant.conditions[1] =
            "Use fresh/empty token state, or a separately designed migration; initialization does not reconstruct prior voting-unit/checkpoint history";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployERC20Votes", "run(string,string,address)", variant, "buildCuts(name_,symbol_,admin)"
        );
    }

    /// @notice Deploys a votes ERC-20 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(string memory name_, string memory symbol_, address admin) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, admin);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }
}
