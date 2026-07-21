// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployCircuitBreaker} from "@lattice-script/base/security/DeployCircuitBreaker.s.sol";
import {CircuitBreakerTestFacet} from "@lattice-test/helpers/CircuitBreakerTestFacet.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {CircuitBreaker} from "@lattice/security/CircuitBreaker.sol";
import {Test} from "forge-std/Test.sol";

/// @title CircuitBreakerTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for CircuitBreaker facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployCircuitBreaker} recipe (ERC165 + AccessControl +
///         CircuitBreaker + the recipe-local init) and APPENDS a test-only {CircuitBreakerTestFacet} exposing the
///         internal `checkNotTripped` consumer guard — so every breaker call and every gated action routes
///         through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides.
abstract contract CircuitBreakerTestBase is Test, GetSelectors {
    DeployCircuitBreaker internal deployer;
    address internal diamond; // the assembled circuit-breaker diamond
    CircuitBreaker internal breaker; // typed handle on the diamond (breaker calls dispatch through it)
    CircuitBreakerTestFacet internal guard; // typed handle for the test-only checkNotTripped gate

    /// @notice Assembles the production CircuitBreaker diamond + the test guard facet with `admin` as the admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed circuit-breaker diamond.
    function _deployCircuitBreaker(address admin) internal returns (address diamond_) {
        deployer = new DeployCircuitBreaker();
        (FacetCut[] memory prod, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        FacetCut[] memory cuts = new FacetCut[](prod.length + 1);
        for (uint256 i; i < prod.length; ++i) {
            cuts[i] = prod[i];
        }
        cuts[prod.length] = FacetCut({
            facetAddress: address(new CircuitBreakerTestFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("CircuitBreakerTestFacet")
        });

        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
