// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {ReentrancyGuardTestFacet} from "@lattice-test/helpers/ReentrancyGuardTestFacet.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {Test} from "forge-std/Test.sol";

/// @title ReentrancyGuardTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ReentrancyGuard tests that exercise the guard on a REAL {Diamond} rather than a flattened
///         inheritance mock. ReentrancyGuard has no standalone production facet (it is a guard consumed by other
///         facets), so `setUp` cuts a bare diamond `[ReentrancyGuardTestFacet]` with no init
///         (the transient guard needs none) — proving reentry reverts under genuine delegatecall dispatch, where the lock
///         lives in the diamond's storage and every `this.*` call re-enters the diamond fallback (the whole point
///         of testing the guard on a real diamond).
abstract contract ReentrancyGuardTestBase is Test, GetSelectors {
    address internal diamond; // the assembled bare guard diamond
    ReentrancyGuardTestFacet internal guarded; // typed handle on the diamond (guarded calls dispatch through it)

    /// @notice Assembles the bare ReentrancyGuard diamond: just the test facet — the transient guard has no init.
    /// @return diamond_ The deployed guard diamond.
    function _deployReentrancyGuard() internal returns (address diamond_) {
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut({
            facetAddress: address(new ReentrancyGuardTestFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("ReentrancyGuardTestFacet")
        });

        LatticeDiamond d = new LatticeDiamond();
        d.initialize(cuts, address(0), "");
        diamond_ = address(d);
    }
}
