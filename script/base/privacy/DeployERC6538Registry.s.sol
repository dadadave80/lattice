// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
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
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC6538Registry} from "@lattice/privacy/ERC6538Registry.sol";
import {ERC6538RegistryInit} from "@lattice/privacy/ERC6538RegistryInit.sol";
import {EIP712} from "@lattice/utils/EIP712.sol";

/// @title DeployERC6538Registry
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-6538 stealth meta-address registry diamond: `ERC165Facet` +
///         `EIP712` + `ERC6538Registry` + {ERC6538RegistryInit}. The ONE source of truth for what a registry
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         Each facet owns ONLY its own selectors (the composability principle): the standalone `EIP712` facet
///         provides the ERC-5267 `eip712Domain()` entry point, and `ERC6538Registry` provides the registry
///         surface. The init seeds the EIP-712 domain.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut; deploy a new diamond to change
///      behavior. Use the ADMIN overload (`buildCuts(..., admin)` / `run(..., admin)`) for an upgradeable
///      deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployERC6538Registry is BaseDeploy {
    /// @notice Builds the ERC-6538 registry diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @return cuts The facet cuts (ERC165 + EIP712 + ERC6538Registry).
    /// @return init The {MultiInit} running {ERC6538RegistryInit} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts() public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) =
            _withImmutableIntrospection(_init("ERC6538RegistryInit"), abi.encodeCall(ERC6538RegistryInit.init, ()));
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(1), _recipeSeams(1));
        (init, initCalldata) = _withAdminUpgradeableIntrospection(
            _init("ERC6538RegistryInit"), abi.encodeCall(ERC6538RegistryInit.init, ()), admin
        );
    }

    /// @dev Ordered facets shared by execution and the exported recipe data.
    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant < 2, "DeployERC6538Registry: unknown variant");
        facets = new RecipeFacet[](variant == 0 ? 4 : 6);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("EIP712");
        facets[2] = RecipePlanLib.all("ERC6538Registry");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        if (variant == 1) {
            facets[4] = RecipePlanLib.all("AccessControl");
            facets[5] = RecipePlanLib.all("AccessControlDiamondCut");
        }
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cuts, external initializer order and authority assignments as script data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC6538Registry", "script/base/privacy/DeployERC6538Registry.s.sol", 2);
        result.deploymentContexts = new RecipeDeploymentContext[](2);
        for (uint256 i; i < 2; ++i) {
            RecipeVariant memory variant;
            variant.id = i == 0 ? "DeployERC6538Registry:buildCuts()" : "DeployERC6538Registry:buildCuts(address)";
            variant.buildSignature = i == 0 ? "buildCuts()" : "buildCuts(address)";
            variant.proxyKind = RecipeProxyKind.Lattice;
            variant.initOutputKind = RecipeInitOutputKind.Single;
            variant.facets = _cutPlan(i);
            variant.seams = _recipeSeams(i);
            variant.inputs = new RecipeParameter[](i == 0 ? 0 : 1);
            RecipeInitStep[] memory module = RecipeSpecLib.emptyLeaf("ERC6538RegistryInit", "init()");
            if (i == 0) {
                variant.initPlan = RecipeSpecLib.introspected(module, false);
            } else {
                variant.inputs[0] = RecipeParameter(
                    "admin",
                    "address",
                    "account",
                    "0x00000000000000000000000000000000000000ad",
                    "caller: choose a usable role and upgrade administrator; initialization permits the zero address"
                );
                variant.initPlan = RecipeSpecLib.adminIntrospected(module, "admin");
            }
            variant.authorities = new RecipeAuthority[](i == 0 ? 0 : 1);
            if (i == 1) {
                variant.authorities[0] = RecipeSpecLib.role(
                    "AccessControl",
                    "DEFAULT_ADMIN_ROLE",
                    "bytes32",
                    bytes32(0),
                    "admin",
                    "role administration and diamondCut; the module business surface remains permissionless"
                );
            }
            variant.conditions = new string[](1);
            variant.conditions[0] =
                "the bundle initializes the EIP712 domain name ERC6538Registry and version 1.0; no domain arguments are builder inputs";
            result.variants[i] = variant;
            result.deploymentContexts[i] = RecipeSpecLib.deploymentContext(
                "DeployERC6538Registry",
                i == 0 ? "run()" : "run(address)",
                variant,
                i == 0 ? "buildCuts()" : "buildCuts(admin)"
            );
        }
    }

    /// @notice Deploys an ERC-6538 registry diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @return registry The deployed registry diamond address.
    function run() external returns (address registry) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts();
        registry = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(address admin) external returns (address registry) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        registry = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
