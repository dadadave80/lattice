// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployInvariantChecker} from "@lattice-script/base/security/DeployInvariantChecker.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {InvariantCheckerTestFacet} from "@lattice-test/helpers/InvariantCheckerTestFacet.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {InvariantChecker} from "@lattice/security/InvariantChecker.sol";
import {Test} from "forge-std/Test.sol";

/// @title InvariantCheckerTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Shared base for the InvariantChecker facet tests ({InvariantCheckerTest} and
///         {InvariantCheckerUsageTest}) that exercise a REAL {Diamond} rather than a flattened inheritance mock.
///         `setUp` assembles the production {DeployInvariantChecker} recipe (ERC165 + AccessControl +
///         InvariantChecker + the recipe-local init) and appends the test-only {InvariantCheckerTestFacet} that
///         re-expresses the usage example's `distributeYield` gate — so both the raw registry API and the opt-in
///         consumer pattern route through the diamond's `delegatecall` dispatch. Exposes a `checker` handle (the
///         registry facet) and a `usage` handle (the gated-action helper facet).
abstract contract InvariantCheckerTestBase is Test, GetSelectors {
    DeployInvariantChecker internal deployer;
    address internal diamond; // the assembled invariant-checker diamond
    InvariantChecker internal checker; // typed handle on the registry facet (dispatches through the diamond)
    InvariantCheckerTestFacet internal usage; // typed handle on the test-only gated-action helper facet

    /// @notice Builds the test-only {InvariantCheckerTestFacet} cut appended on top of the production recipe.
    function _usageCut() internal returns (FacetCut memory) {
        return FacetCut({
            facetAddress: address(new InvariantCheckerTestFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("InvariantCheckerTestFacet")
        });
    }

    /// @notice Assembles the production InvariantChecker diamond (+ the usage helper facet) with `admin` as the
    ///         invariant-registration admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed invariant-checker diamond.
    function _deployInvariantChecker(address admin) internal returns (address diamond_) {
        deployer = new DeployInvariantChecker();
        (FacetCut[] memory prod, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        FacetCut[] memory cuts = new FacetCut[](prod.length + 1);
        for (uint256 i; i < prod.length; ++i) {
            cuts[i] = prod[i];
        }
        cuts[prod.length] = _usageCut();

        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
