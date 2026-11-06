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

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {AccountDeployBase} from "@lattice-script/base/accounts/AccountDeployBase.s.sol";
import {AccountReleaseInventory} from "@lattice-script/lib/AccountReleaseInventory.sol";
import {LatticeVersion} from "@lattice/LatticeVersion.sol";
import {AccountInit6900} from "@lattice/accounts/erc6900/AccountInit6900.sol";
import {DEFAULT_ENTRY_POINT} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {IAccountFactory} from "@lattice/interfaces/accounts/IAccountFactory.sol";

/// @title DeployAccount6900
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Canonical ERC-6900 modular account recipe. The shared release blueprint fixes its facet set;
///         the EntryPoint-specific factory creates and initializes the specialized fallback proxy atomically.
/// @dev Canonical EntryPoints reuse the release's constructor-bound init/factory identities. Other EntryPoints
///      use an explicit custom identity whose initcode still binds the EntryPoint and ordered blueprint.
contract DeployAccount6900 is AccountDeployBase {
    /// @notice Build released facet cuts and the constructor-bound initializer, without creating an account.
    /// @param entryPoint_ Trusted ERC-4337 EntryPoint; chain availability is a deployment precondition.
    function buildCuts(address entryPoint_) public returns (FacetCut[] memory cuts, AccountInit6900 init) {
        cuts = _accountCuts(true, LatticeVersion.VERSION);
        init =
            AccountInit6900(_accountInit(AccountReleaseInventory.describe(true, entryPoint_), LatticeVersion.VERSION));
    }

    /// @notice Resolve or deploy the specialized account factory for this exact EntryPoint and blueprint.
    function buildFactory(address entryPoint_) public returns (IAccountFactory factory) {
        (,, address at) = _accountRelease(AccountReleaseInventory.describe(true, entryPoint_), LatticeVersion.VERSION);
        factory = IAccountFactory(at);
    }

    /// @notice Create an account, or return the existing account for the same owner and LATTICE_SALT.
    function run(address entryPoint_, address owner) external returns (address account) {
        return _run(entryPoint_, owner, vm.envOr("LATTICE_SALT", bytes32(0)));
    }

    /// @notice Explicit-salt deployment, with the same idempotent semantics as the account factory.
    function run(address entryPoint_, address owner, bytes32 salt) external returns (address account) {
        return _run(entryPoint_, owner, salt);
    }

    /// @notice Use the repository's default EntryPoint (v0.9).
    function run(address owner) external returns (address account) {
        return _run(DEFAULT_ENTRY_POINT, owner, vm.envOr("LATTICE_SALT", bytes32(0)));
    }

    /// @notice Constructor-bound account topology; runtime owner/salt belong to deployment contexts.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployAccount6900", "script/base/accounts/DeployAccount6900.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployAccount6900:buildCuts(address)";
        variant.buildSignature = "buildCuts(address)";
        variant.proxyKind = RecipeProxyKind.ModularAccount6900;
        variant.initOutputKind = RecipeInitOutputKind.Account;
        variant.facets = _accountCutPlan(true);
        variant.seams = new RecipeSeam[](0);
        variant.inputs = new RecipeParameter[](1);
        variant.inputs[0] = RecipeParameter(
            "entryPoint_",
            "address",
            "ERC4337-EntryPoint",
            "0x433709009b8330fda32311df1c2afa402ed8d009",
            "constructor permits zero; runtime account initialization rejects zero; caller authenticates EntryPoint code and chain support"
        );
        RecipeParameter[] memory runtimeParameters = new RecipeParameter[](1);
        runtimeParameters[0] = RecipeParameter(
            "owner",
            "address",
            "account",
            "0x00000000000000000000000000000000000000ad",
            "caller chooses a usable module administrator; ERC6900 initialization permits zero"
        );
        string[] memory runtimeBindings = new string[](1);
        runtimeBindings[0] = "factory.createAccount.owner";
        variant.initPlan = RecipeSpecLib.leaf("AccountInit6900", "init(address)", runtimeParameters, runtimeBindings);
        variant.initPlan[0].constructorBound = true;
        variant.initPlan[0].constructorParameters = variant.inputs;
        variant.initPlan[0].constructorBindings = new string[](1);
        variant.initPlan[0].constructorBindings[0] = "entryPoint_";
        variant.authorities = new RecipeAuthority[](2);
        variant.authorities[0] = RecipeSpecLib.owner(
            "diamond-lib Ownable",
            "diamond-self",
            "unrouted Ownable word gates DiamondCutFacet; validated self-call required"
        );
        variant.authorities[1] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "factory.createAccount.owner",
            "installs and removes validation/execution modules"
        );
        variant.conditions = new string[](5);
        variant.conditions[0] =
            "The canonical release catalog contains EntryPoint v0.7/v0.8/v0.9 pairs; custom EntryPoints have explicit custom identities and constructor-bound hashes";
        variant.conditions[1] =
            "Initializer name refers to the constructor artifact; accountProfiles and the frozen release manifest bind each canonical EntryPoint to its exact release label/factory";
        variant.conditions[2] =
            "Factory runtime codehash does not bind stored cuts; select exact constructor-bound manifest identity, never infer factory blueprint from codehash";
        variant.conditions[3] =
            "The supplied owner receives DEFAULT_ADMIN_ROLE; the unrouted Ownable cut-gate word is diamond-self; this blueprint exposes no owner() route";
        variant.conditions[4] =
            "An initial validation module is not installed; the administrator must install reviewed validation/execution modules before normal ERC4337 use";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](4);
        {
            RecipeDeploymentContext memory context;
            context.id = "DeployAccount6900:buildFactory(address)";
            context.signature = "buildFactory(address)";
            context.createsProxy = false;
            context.variants = new string[](1);
            context.variants[0] = variant.id;
            context.inputs = new RecipeParameter[](1);
            context.inputs[0] = variant.inputs[0];
            context.bindings = new string[](2);
            context.bindings[0] = "AccountReleaseInventory.describe(entryPoint_)";
            context.bindings[1] = "constructor-bound specialized factory for exact cuts and init";
            context.conditions = new string[](1);
            context.conditions[0] = "resolves or deploys the shared factory; does not create an account";
            result.deploymentContexts[0] = context;
        }
        {
            RecipeDeploymentContext memory context;
            context.id = "DeployAccount6900:run(address,address)";
            context.signature = "run(address,address)";
            context.createsProxy = true;
            context.variants = new string[](1);
            context.variants[0] = variant.id;
            context.inputs = new RecipeParameter[](2);
            context.inputs[0] = variant.inputs[0];
            context.inputs[1] = runtimeParameters[0];
            context.bindings = new string[](1);
            context.bindings[0] = "buildFactory(entryPoint_).createAccount(owner,env.LATTICE_SALT)";
            context.conditions = new string[](1);
            context.conditions[0] = "LATTICE_SALT defaults to bytes32(0); same owner/salt returns the existing account";
            result.deploymentContexts[1] = context;
        }
        {
            RecipeDeploymentContext memory context;
            context.id = "DeployAccount6900:run(address,address,bytes32)";
            context.signature = "run(address,address,bytes32)";
            context.createsProxy = true;
            context.variants = new string[](1);
            context.variants[0] = variant.id;
            context.inputs = new RecipeParameter[](3);
            context.inputs[0] = variant.inputs[0];
            context.inputs[1] = runtimeParameters[0];
            context.inputs[2] = RecipeParameter(
                "salt",
                "bytes32",
                "owner-counterfactual-salt",
                "0x0000000000000000000000000000000000000000000000000000000000000001",
                "factory getAddress and createAccount use the same owner/salt formula"
            );
            context.bindings = new string[](1);
            context.bindings[0] = "buildFactory(entryPoint_).createAccount(owner,salt)";
            context.conditions = new string[](1);
            context.conditions[0] = "same owner/salt returns the existing account";
            result.deploymentContexts[2] = context;
        }
        {
            RecipeDeploymentContext memory context;
            context.id = "DeployAccount6900:run(address)";
            context.signature = "run(address)";
            context.createsProxy = true;
            context.variants = new string[](1);
            context.variants[0] = variant.id;
            context.inputs = new RecipeParameter[](1);
            context.inputs[0] = runtimeParameters[0];
            context.bindings = new string[](2);
            context.bindings[0] = "entryPoint_=DEFAULT_ENTRY_POINT(v0.9)";
            context.bindings[1] = "buildFactory(entryPoint_).createAccount(owner,env.LATTICE_SALT)";
            context.conditions = new string[](1);
            context.conditions[0] =
                "LATTICE_SALT defaults to bytes32(0); default EntryPoint code/chain availability remains a caller precondition";
            result.deploymentContexts[3] = context;
        }
    }

    function _run(address entryPoint_, address owner, bytes32 salt) private returns (address account) {
        vm.startBroadcast();
        account = buildFactory(entryPoint_).createAccount(owner, salt);
        vm.stopBroadcast();
    }
}
