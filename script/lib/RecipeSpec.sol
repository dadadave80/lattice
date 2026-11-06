// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCutAction} from "@diamond/libraries/DiamondLib.sol";

/// @notice The fallback proxy required by a recipe; account proxies cannot be replaced by a plain Lattice.
enum RecipeProxyKind {
    Lattice,
    AccountDiamond,
    ModularAccount6900
}

/// @notice All means the facet's exported business selectors; ERC-8153 exportSelectors is never routed.
enum RecipeSelectorSelection {
    All,
    Except,
    Only
}

/// @notice The builder's output shape; parallel initializers gain their outer MultiInit during assembly.
enum RecipeInitOutputKind {
    Single,
    Parallel,
    Account
}

/// @notice One ordered cut declaration. Repeated facet names represent distinct Add and Replace operations.
struct RecipeFacet {
    string name;
    FacetCutAction action;
    RecipeSelectorSelection selection;
    bytes4[] selectors;
}

/// @notice An ownership obligation activated when all named participants are present in the recipe.
/// @dev An exclusion, manual subset omission or Replace must name a seam containing that facet and selector.
struct RecipeSeam {
    string id;
    bytes4 selector;
    string[] participants;
    string[] allowedOwners;
    bool allowUnrouted;
    string reason;
}

/// @notice A documented input or initializer argument. Examples are JSON values or explicitly named templates.
/// @dev Units and rules describe source-enforced constraints or caller obligations; they do not certify providers.
struct RecipeParameter {
    string name;
    string abiType;
    string unit;
    string example;
    string rule;
}

/// @notice One external initializer call in a parent-indexed tree, preserving nested MultiInit wrappers.
/// @dev The root parent is type(uint256).max. Bindings describe typed source expressions and are never executed.
///      Bundle-internal module phases remain the initializer's compiler composition metadata, including qualifiers.
struct RecipeInitStep {
    string name;
    string signature;
    uint256 parent;
    bool constructorBound;
    RecipeParameter[] constructorParameters;
    string[] constructorBindings;
    RecipeParameter[] parameters;
    string[] bindings;
}

enum RecipeAuthorityKind {
    RoleGrant,
    Ownership,
    ExternalAuthority
}

/// @notice An assigned authority, distinguishing real role grants from ownership and pinned external authority.
/// @dev roleId is the exact constant, not a hash inferred from its name; roleType retains uint64/bytes32 distinctions.
struct RecipeAuthority {
    RecipeAuthorityKind kind;
    string module;
    string role;
    string roleType;
    bytes32 roleId;
    string grantee;
    string reason;
}

/// @notice One canonical builder signature and configuration profile; IDs are qualified by recipe name.
struct RecipeVariant {
    string id;
    string buildSignature;
    RecipeProxyKind proxyKind;
    RecipeInitOutputKind initOutputKind;
    RecipeFacet[] facets;
    RecipeSeam[] seams;
    RecipeInitStep[] initPlan;
    RecipeParameter[] inputs;
    RecipeAuthority[] authorities;
    string[] conditions;
}

/// @notice A public deployment or factory-resolution entrypoint, separate from its builder's ABI inputs.
/// @dev In particular, account owner/salt and a default EntryPoint belong here, not in buildCuts(address).
///      Bindings describe source calls and environment defaults; consumers must not execute them as expressions.
struct RecipeDeploymentContext {
    string id;
    string signature;
    bool createsProxy;
    string[] variants;
    RecipeParameter[] inputs;
    string[] bindings;
    string[] conditions;
}

/// @notice All public builder variants of one canonical recipe, including explicitly inherited builder contexts.
struct RecipeSpec {
    string name;
    string source;
    RecipeVariant[] variants;
    RecipeDeploymentContext[] deploymentContexts;
}

/// @title IRecipeSpec
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Script-only recipe data for composition tools; it does not execute a builder or deploy implementations.
interface IRecipeSpec {
    function recipeSpec() external pure returns (RecipeSpec memory);
}
