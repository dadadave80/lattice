// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {CircuitBreaker} from "@lattice/security/CircuitBreaker.sol";
import {CircuitBreakerLib} from "@lattice/security/libraries/CircuitBreakerLib.sol";

/// @notice Recipe-local init: seeds AccessControl and registers ICircuitBreaker. Composed inline —
///         `CircuitBreakerLib.__CircuitBreaker_init()` is callable from any init, so no standalone production
///         init artifact exists. MUST be invoked via the diamond's `initialize` `_init` delegatecall.
contract CircuitBreakerRecipeInit {
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the breaker configuration).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        CircuitBreakerLib.__CircuitBreaker_init();
    }
}

/// @title DeployCircuitBreaker
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a CircuitBreaker diamond: `ERC165Facet` + `AccessControl` +
///         `CircuitBreaker` + a recipe-local init. The ONE source of truth for what a circuit-breaker diamond
///         is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because `setThreshold`/`recordObservation`/`reset` are
///         `DEFAULT_ADMIN_ROLE`-gated.
contract DeployCircuitBreaker is BaseDeploy {
    /// @notice Builds the CircuitBreaker diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the breaker configuration).
    /// @return cuts The facet cuts (ERC165 + AccessControl + CircuitBreaker + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {CircuitBreakerRecipeInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new CircuitBreaker()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new CircuitBreakerRecipeInit()), abi.encodeCall(CircuitBreakerRecipeInit.init, (admin))
        );
    }

    /// @notice Deploys a CircuitBreaker diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The breaker admin.
    /// @return breaker The deployed circuit-breaker diamond address.
    function run(address admin) external returns (address breaker) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        breaker = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
