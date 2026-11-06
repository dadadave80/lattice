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
import {ERC3643_AGENT_ROLE} from "@lattice/tokens/ERC3643/libraries/ERC3643AgentRoleLib.sol";

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {ERC3643Init} from "@lattice/tokens/ERC3643/ERC3643Init.sol";
import {ERC3643Params} from "@lattice/tokens/ERC3643/ERC3643Params.sol";

/// @title DeployERC3643
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice The reviewed immutable ERC-3643 composition, initialized atomically by LatticeFactory.
/// @dev No cut, arbitrary execution, delegatecall, permit, vote/vault or other accounting facet is installed.
///      The canonical initializer checks all runtime hashes and exact required selector routes. External
///      storage must pre-bind the predicted registry/token address; external compliance must be pre-bound
///      or genuinely authorize the token to bind it. No custom initializer or approved-hash list is accepted.
contract DeployERC3643 is BaseDeploy {
    function buildCuts(ERC3643Params memory config)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(config.temporaryApproval ? 1 : 0), _recipeSeams(0));
        init = _init("ERC3643Init");
        initCalldata = abi.encodeCall(ERC3643Init.init, (config));
    }

    function run(ERC3643Params memory config) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory data) = buildCuts(config);
        token = _assemble(cuts, init, data);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory cuts) {
        require(variant < 2, "DeployERC3643: unknown variant");
        string[10] memory names = [
            "ERC165Facet",
            "OwnableFacet",
            "DiamondLoupeFacet",
            "ERC3643",
            "ERC3643AgentRole",
            "ERC3643IdentityRegistry",
            "ERC3643IdentityRegistryStorage",
            "ERC3643TrustedIssuersRegistry",
            "ERC3643ClaimTopicsRegistry",
            "ERC3643Compliance"
        ];
        cuts = new RecipeFacet[](variant == 0 ? 10 : 11);
        for (uint256 i; i < names.length; ++i) {
            cuts[i] = RecipePlanLib.all(names[i]);
        }
        if (variant == 1) cuts[10] = RecipePlanLib.all("ERC20TemporaryApproval");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC3643", "script/base/tokens/DeployERC3643.s.sol", 2);
        for (uint256 i; i < 2; ++i) {
            RecipeVariant memory variant;
            variant.buildSignature = "buildCuts((address,address[],string,string,uint8,address,address,address,bool))";
            variant.id = i == 0 ? "DeployERC3643:temporaryApproval=false" : "DeployERC3643:temporaryApproval=true";
            variant.proxyKind = RecipeProxyKind.Lattice;
            variant.initOutputKind = RecipeInitOutputKind.Single;
            variant.facets = _cutPlan(i);
            variant.seams = _recipeSeams(i);
            variant.inputs = new RecipeParameter[](9);
            variant.inputs[0] = RecipeParameter(
                "config.owner",
                "address",
                "owner-authority",
                "0x00000000000000000000000000000000000000ad",
                "enforced: nonzero owner"
            );
            variant.inputs[1] = RecipeParameter(
                "config.agents",
                "address[]",
                "agent-authorities",
                "[]",
                "enforced: every element nonzero; empty and duplicates allowed"
            );
            variant.inputs[2] =
                RecipeParameter("config.name", "string", "metadata", "Permissioned Token", "no length constraint");
            variant.inputs[3] = RecipeParameter("config.symbol", "string", "metadata", "PERM", "no length constraint");
            variant.inputs[4] = RecipeParameter(
                "config.decimals", "uint8", "decimal-places", "18", "ABI uint8 only; no init <=18 clamp"
            );
            variant.inputs[5] = RecipeParameter(
                "config.onchainID",
                "address",
                "token-identity",
                "0x0000000000000000000000000000000000000000",
                "zero permitted; caller authenticates configured token identity"
            );
            variant.inputs[6] = RecipeParameter(
                "config.identityStorage",
                "address",
                "identity-registry-storage",
                "0x0000000000000000000000000000000000000000",
                "zero selects diamond-self; external code must already bind the predicted registry/token address"
            );
            variant.inputs[7] = RecipeParameter(
                "config.compliance",
                "address",
                "compliance-policy",
                "0x0000000000000000000000000000000000000000",
                "zero selects diamond-self; external code must already bind token or genuinely authorize its binding"
            );
            variant.inputs[8] = RecipeParameter(
                "config.temporaryApproval",
                "bool",
                "profile-switch",
                i == 0 ? "false" : "true",
                i == 0 ? "profile: false" : "profile: true"
            );
            string[] memory bindings = new string[](9);
            for (uint256 j; j < bindings.length; ++j) {
                bindings[j] = variant.inputs[j].name;
            }
            variant.initPlan = RecipeSpecLib.leaf(
                "ERC3643Init",
                "init((address,address[],string,string,uint8,address,address,address,bool))",
                variant.inputs,
                bindings
            );
            variant.authorities = new RecipeAuthority[](2);
            variant.authorities[0] = RecipeSpecLib.owner(
                "Ownable", "config.owner", "OwnableFacet governs component configuration; no cut facet installed"
            );
            variant.authorities[1] = RecipeSpecLib.role(
                "ERC3643AgentRole",
                "ERC3643_AGENT_ROLE",
                "bytes32",
                ERC3643_AGENT_ROLE,
                "each config.agents element",
                "retained explicit agent memberships; no DEFAULT_ADMIN_ROLE bootstrap grant"
            );
            variant.conditions = new string[](5);
            variant.conditions[0] =
                "Closed immutable profile: admission validates exact proxy/facet runtime hashes and selector routes both before and after external initialization callbacks";
            variant.conditions[1] =
                "No ERC20 base facet, arbitrary execution, custom initializer, approved-hash allowlist, permit, votes, vault or cut route may be added to this profile";
            variant.conditions[2] =
                "External identity storage and compliance require predeployment counterfactual binding/authorization; caller authenticates all external component behavior";
            variant.conditions[3] =
                "Claim topics, trusted issuers and investor identities require post-deployment setup; tokens start paused and an explicitly configured agent must unpause after setup; owner is not implicitly an agent and no DEFAULT_ADMIN_ROLE is granted";
            variant.conditions[4] =
                "Both profiles require Cancun EIP1153: the ERC3643 execution lock and shared allowance spending use native transient storage even when temporaryApproval=false";
            result.variants[i] = variant;
        }
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeDeploymentContext memory context = RecipeSpecLib.deploymentContext(
            "DeployERC3643",
            "run((address,address[],string,string,uint8,address,address,address,bool))",
            result.variants[0],
            "buildCuts(config)"
        );
        context.inputs = new RecipeParameter[](result.variants[0].inputs.length);
        for (uint256 i; i < context.inputs.length; ++i) {
            context.inputs[i] = result.variants[0].inputs[i];
        }
        context.inputs[8] = RecipeParameter(
            "config.temporaryApproval",
            "bool",
            "profile-switch",
            "false",
            "false selects the base profile; true selects temporary approval; both profiles require Cancun EIP1153"
        );
        context.variants = new string[](2);
        context.variants[0] = result.variants[0].id;
        context.variants[1] = result.variants[1].id;
        context.conditions = new string[](1);
        context.conditions[0] = "config.temporaryApproval selects the matching explicit profile";
        result.deploymentContexts[0] = context;
    }
}
