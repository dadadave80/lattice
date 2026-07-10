// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {ReentrancyGuardTestFacet} from "@lattice-test/helpers/ReentrancyGuardTestFacet.sol";
import {ReentrancyGuardInit} from "@lattice/security/ReentrancyGuardInit.sol";
import {Test} from "forge-std/Test.sol";

/// @title ReentrancyGuardTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ReentrancyGuard tests that exercise the guard on a REAL {Diamond} rather than a flattened
///         inheritance mock. ReentrancyGuard has no standalone production facet (it is a guard consumed by other
///         facets), so `setUp` cuts a bare diamond `[ERC165Facet, ReentrancyGuardTestFacet]` and runs
///         {ReentrancyGuardInit} — proving reentry reverts under genuine delegatecall dispatch, where the lock
///         lives in the diamond's storage and every `this.*` call re-enters the diamond fallback (the whole point
///         of testing the guard on a real diamond).
abstract contract ReentrancyGuardTestBase is Test, GetSelectors {
    address internal diamond; // the assembled bare guard diamond
    ReentrancyGuardTestFacet internal guarded; // typed handle on the diamond (guarded calls dispatch through it)

    /// @notice Assembles the bare ReentrancyGuard diamond: ERC165 + the test facet + {ReentrancyGuardInit}.
    /// @return diamond_ The deployed guard diamond.
    function _deployReentrancyGuard() internal returns (address diamond_) {
        FacetCut[] memory cuts = new FacetCut[](2);
        cuts[0] = FacetCut({
            facetAddress: address(new ERC165Facet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("ERC165Facet")
        });
        cuts[1] = FacetCut({
            facetAddress: address(new ReentrancyGuardTestFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("ReentrancyGuardTestFacet")
        });

        address init = address(new ReentrancyGuardInit());
        bytes memory initCalldata = abi.encodeCall(ReentrancyGuardInit.init, ());

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
