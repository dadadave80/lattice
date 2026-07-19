// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {RateLimiter} from "@lattice/security/RateLimiter.sol";
import {RateLimiterLib} from "@lattice/security/libraries/RateLimiterLib.sol";

/// @notice Recipe-local init: seeds AccessControl and registers IRateLimiter. Composed inline —
///         `RateLimiterLib.__RateLimiter_init()` is callable from any init, so no standalone production
///         init artifact exists. MUST be invoked via the diamond's `initialize` `_init` delegatecall.
contract RateLimiterRecipeInit {
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls `configure`).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        RateLimiterLib.__RateLimiter_init();
    }
}

/// @title DeployRateLimiter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a RateLimiter diamond: `ERC165Facet` + `AccessControl` + `RateLimiter`
///         + a recipe-local init. The ONE source of truth for what a rate-limited diamond is, shared by production
///         (`run --broadcast`) and the facet tests (which build on {buildCuts}). `AccessControl` is part of the
///         base recipe because `configure` is `DEFAULT_ADMIN_ROLE`-gated.
contract DeployRateLimiter is BaseDeploy {
    /// @notice Builds the RateLimiter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls `configure`).
    /// @return cuts The facet cuts (ERC165 + AccessControl + RateLimiter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {RateLimiterRecipeInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new RateLimiter()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new RateLimiterRecipeInit()), abi.encodeCall(RateLimiterRecipeInit.init, (admin))
        );
    }

    /// @notice Deploys a RateLimiter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The rate-limit admin.
    /// @return rateLimiter The deployed rate-limiter diamond address.
    function run(address admin) external returns (address rateLimiter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        rateLimiter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
