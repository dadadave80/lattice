// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {CircuitBreaker} from "@lattice/security/CircuitBreaker.sol";
import {CircuitBreakerInit} from "@lattice/security/CircuitBreakerInit.sol";

/// @title DeployCircuitBreaker
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a CircuitBreaker diamond: `ERC165Facet` + `AccessControl` +
///         `CircuitBreaker` + {CircuitBreakerInit}. The ONE source of truth for what a circuit-breaker diamond
///         is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because `setThreshold`/`recordObservation`/`reset` are
///         `DEFAULT_ADMIN_ROLE`-gated.
contract DeployCircuitBreaker is BaseDeploy {
    /// @notice Builds the CircuitBreaker diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the breaker configuration).
    /// @return cuts The facet cuts (ERC165 + AccessControl + CircuitBreaker).
    /// @return init The {CircuitBreakerInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new CircuitBreaker()));
        init = address(new CircuitBreakerInit());
        initCalldata = abi.encodeCall(CircuitBreakerInit.init, (admin));
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
