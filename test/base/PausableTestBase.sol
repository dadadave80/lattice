// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployPausable} from "@lattice-script/base/security/DeployPausable.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {PausableTestFacet} from "@lattice-test/helpers/PausableTestFacet.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {Test} from "forge-std/Test.sol";

/// @title PausableTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for Pausable facet tests that exercise a REAL {Diamond} rather than a flattened inheritance mock.
///         `setUp` assembles the production {DeployPausable} recipe (ERC165 + AccessControl + Pausable +
///         {PausableInit}) and APPENDS a test-only {PausableTestFacet} exposing the internal
///         `whenNotPaused`/`whenPaused` guards — so every pause call and every guarded action routes through the
///         diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides.
abstract contract PausableTestBase is Test, GetSelectors {
    DeployPausable internal deployer;
    address internal diamond; // the assembled pausable diamond
    Pausable internal pausable; // typed handle on the diamond (pause calls dispatch through it)
    PausableTestFacet internal guard; // typed handle for the test-only whenNotPaused/whenPaused gates

    /// @notice Assembles the production Pausable diamond + the test guard facet with `admin` as the pause admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed pausable diamond.
    function _deployPausable(address admin) internal returns (address diamond_) {
        deployer = new DeployPausable();
        (FacetCut[] memory prod, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        FacetCut[] memory cuts = new FacetCut[](prod.length + 1);
        for (uint256 i; i < prod.length; ++i) {
            cuts[i] = prod[i];
        }
        cuts[prod.length] = FacetCut({
            facetAddress: address(new PausableTestFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("PausableTestFacet")
        });

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
