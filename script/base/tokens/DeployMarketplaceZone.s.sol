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
    RecipeParameter,
    RecipeProxyKind,
    RecipeSeam,
    RecipeSpec,
    RecipeVariant
} from "@lattice-script/lib/RecipeSpec.sol";
import {RecipeSpecLib} from "@lattice-script/lib/RecipeSpecLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {MarketplaceZone} from "@lattice/tokens/MarketplaceZone.sol";
import {MarketplaceZoneInit} from "@lattice/tokens/MarketplaceZoneInit.sol";

/// @title DeployMarketplaceZone
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Seaport zone diamond: `ERC165Facet` + `AccessControl` + the
///         {MarketplaceZone} facet, seeded by {MarketplaceZoneInit}. The diamond acts as the `zone` for RESTRICTED
///         Seaport orders — `authorizeOrder` enforces pause + blocklist and `validateOrder` enforces ERC-2981
///         royalties, both gated/configured through the co-cut `AccessControl` role surface (`admin` gets
///         DEFAULT_ADMIN_ROLE). `buildCuts` is the broadcast-free primitive the zone facet test reuses; `run`
///         broadcasts.
contract DeployMarketplaceZone is BaseDeploy {
    /// @notice Builds the marketplace zone diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return cuts The facet cuts (ERC165 + AccessControl + MarketplaceZone + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {MarketplaceZoneInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("MarketplaceZoneInit"), abi.encodeCall(MarketplaceZoneInit.init, (admin))
        );
    }

    function _cutPlan(uint256) internal pure returns (RecipeFacet[] memory facets) {
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("MarketplaceZone");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice The zone cut/init plan, actual role grant and marketplace policy limits as script-only data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployMarketplaceZone", "script/base/tokens/DeployMarketplaceZone.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployMarketplaceZone:buildCuts(address)";
        variant.buildSignature = "buildCuts(address)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Single;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](1);
        variant.inputs[0] = RecipeParameter(
            "admin",
            "address",
            "account",
            "0x00000000000000000000000000000000000000ad",
            "caller: choose a usable zone policy, role and upgrade administrator; initialization permits the zero address"
        );
        RecipeParameter[] memory parameters = new RecipeParameter[](1);
        parameters[0] = RecipeParameter(
            "admin_", "address", variant.inputs[0].unit, variant.inputs[0].example, variant.inputs[0].rule
        );
        string[] memory bindings = new string[](1);
        bindings[0] = "admin";
        variant.initPlan = RecipeSpecLib.introspected(
            RecipeSpecLib.leaf("MarketplaceZoneInit", "init(address)", parameters, bindings), true
        );
        variant.authorities = new RecipeAuthority[](1);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "pause/royalty policy, blocklist role administration and diamondCut"
        );
        variant.conditions = new string[](4);
        variant.conditions[0] =
            "the bundle initializes AccessControl then MarketplaceZone; it grants no MARKETPLACE_BLOCKED_ROLE, and fresh deployments start unpaused with no royalty-required collections";
        variant.conditions[1] =
            "caller: configure collection royalty opt-ins and blocked participants separately, and use restricted marketplace orders that actually invoke the zone hooks";
        variant.conditions[2] =
            "authorizeOrder checks pause and the offerer/fulfiller blocklist; validateOrder checks opted-in royalties; both are view-only policy checks callable by any sender, with no pinned Seaport caller address";
        variant.conditions[3] =
            "for opted-in royalty orders, v1 rejects bid-side NFTs, multiple opted-in offer NFTs, mixed fungible payment currencies, zero gross payment or unavailable royaltyInfo instead of bypassing the configured policy";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] =
            RecipeSpecLib.deploymentContext("DeployMarketplaceZone", "run(address)", variant, "buildCuts(admin)");
    }

    /// @notice Deploys a marketplace zone diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The role admin.
    /// @return zone The deployed marketplace zone diamond address.
    function run(address admin) external returns (address zone) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        zone = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
