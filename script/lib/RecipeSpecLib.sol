// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    RecipeAuthority,
    RecipeAuthorityKind,
    RecipeDeploymentContext,
    RecipeInitStep,
    RecipeParameter,
    RecipeSpec,
    RecipeVariant
} from "@lattice-script/lib/RecipeSpec.sol";

/// @title RecipeSpecLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Pure script-data constructors; initializer bindings are descriptions, never an ABI interpreter.
library RecipeSpecLib {
    function spec(string memory name, string memory source, uint256 variants)
        internal
        pure
        returns (RecipeSpec memory result)
    {
        result.name = name;
        result.source = source;
        result.variants = new RecipeVariant[](variants);
    }

    function leaf(
        string memory name,
        string memory signature,
        RecipeParameter[] memory parameters,
        string[] memory bindings
    ) internal pure returns (RecipeInitStep[] memory steps) {
        steps = new RecipeInitStep[](1);
        steps[0].name = name;
        steps[0].signature = signature;
        steps[0].parent = type(uint256).max;
        steps[0].parameters = parameters;
        steps[0].bindings = bindings;
    }

    function emptyLeaf(string memory name, string memory signature) internal pure returns (RecipeInitStep[] memory) {
        return leaf(name, signature, new RecipeParameter[](0), new string[](0));
    }

    function tokenBase(string memory initializer, string memory nameBinding, string memory symbolBinding)
        internal
        pure
        returns (RecipeInitStep[] memory)
    {
        RecipeParameter[] memory parameters = new RecipeParameter[](2);
        parameters[0] = RecipeParameter("name_", "string", "metadata", "Example Token", "no length constraint");
        parameters[1] = RecipeParameter("symbol_", "string", "metadata", "EXM", "no length constraint");
        string[] memory bindings = new string[](2);
        bindings[0] = nameBinding;
        bindings[1] = symbolBinding;
        return introspected(leaf(initializer, "init(string,string)", parameters, bindings), false);
    }

    function aclAdministrator(string memory name) internal pure returns (RecipeParameter memory) {
        return RecipeParameter(
            name,
            "address",
            "account",
            "0x00000000000000000000000000000000000000ad",
            "caller: choose a usable role administrator; AccessControl initialization permits the zero address"
        );
    }

    function deploymentContext(
        string memory recipe,
        string memory signature,
        RecipeVariant memory variant,
        string memory builderCall
    ) internal pure returns (RecipeDeploymentContext memory context) {
        context.id = string.concat(recipe, ":", signature);
        context.signature = signature;
        context.createsProxy = true;
        context.variants = new string[](1);
        context.variants[0] = variant.id;
        context.inputs = variant.inputs;
        context.bindings = new string[](1);
        context.bindings[0] = builderCall;
        context.conditions = new string[](0);
    }

    function role(
        string memory module,
        string memory name,
        string memory roleType,
        bytes32 roleId,
        string memory grantee,
        string memory reason
    ) internal pure returns (RecipeAuthority memory) {
        return RecipeAuthority(RecipeAuthorityKind.RoleGrant, module, name, roleType, roleId, grantee, reason);
    }

    function owner(string memory module, string memory grantee, string memory reason)
        internal
        pure
        returns (RecipeAuthority memory)
    {
        return RecipeAuthority(RecipeAuthorityKind.Ownership, module, "owner", "address", bytes32(0), grantee, reason);
    }

    function externalAuthority(string memory module, string memory name, string memory grantee, string memory reason)
        internal
        pure
        returns (RecipeAuthority memory)
    {
        return
            RecipeAuthority(RecipeAuthorityKind.ExternalAuthority, module, name, "address", bytes32(0), grantee, reason);
    }

    /// @notice Preserve the complete ordered wrapper tree, with each child's original root under a new MultiInit.
    function wrap(RecipeInitStep[][] memory children) internal pure returns (RecipeInitStep[] memory steps) {
        uint256 count = 1;
        for (uint256 i; i < children.length; ++i) {
            count += children[i].length;
        }
        steps = new RecipeInitStep[](count);
        RecipeParameter[] memory parameters = new RecipeParameter[](2);
        parameters[0] = RecipeParameter(
            "_initAddresses", "address[]", "ordered-initializer-targets", "children.targets", "fixed ordered children"
        );
        parameters[1] = RecipeParameter(
            "_initData", "bytes[]", "encoded-initializer-calls", "children.calldata", "one call per target"
        );
        string[] memory bindings = new string[](2);
        bindings[0] = "children.targets";
        bindings[1] = "children.calldata";
        steps[0] = leaf("MultiInit", "multiInit(address[],bytes[])", parameters, bindings)[0];
        uint256 offset = 1;
        for (uint256 i; i < children.length; ++i) {
            for (uint256 j; j < children[i].length; ++j) {
                RecipeInitStep memory step = children[i][j];
                steps[offset + j] = RecipeInitStep({
                    name: step.name,
                    signature: step.signature,
                    parent: step.parent == type(uint256).max ? 0 : offset + step.parent,
                    constructorBound: step.constructorBound,
                    constructorParameters: step.constructorParameters,
                    constructorBindings: step.constructorBindings,
                    parameters: step.parameters,
                    bindings: step.bindings
                });
            }
            offset += children[i].length;
        }
    }

    function introspected(RecipeInitStep[] memory module, bool upgradeable)
        internal
        pure
        returns (RecipeInitStep[] memory)
    {
        RecipeInitStep[][] memory children = new RecipeInitStep[][](2);
        children[0] = module;
        children[1] = emptyLeaf("DiamondIntrospectionInit", upgradeable ? "initUpgradeable()" : "initImmutable()");
        return wrap(children);
    }

    function adminIntrospected(RecipeInitStep[] memory module, string memory adminBinding)
        internal
        pure
        returns (RecipeInitStep[] memory)
    {
        RecipeParameter[] memory parameters = new RecipeParameter[](1);
        parameters[0] = RecipeParameter(
            "admin",
            "address",
            "account",
            "0x00000000000000000000000000000000000000ad",
            "caller: choose a usable upgrade authority; initialization permits the zero address"
        );
        string[] memory bindings = new string[](1);
        bindings[0] = adminBinding;
        RecipeInitStep[][] memory children = new RecipeInitStep[][](3);
        children[0] = module;
        children[1] = leaf("AccessControlInit", "init(address)", parameters, bindings);
        children[2] = emptyLeaf("DiamondIntrospectionInit", "initUpgradeable()");
        return wrap(children);
    }
}
