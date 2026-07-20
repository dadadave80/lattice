// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployMulticall} from "@lattice-script/base/utils/DeployMulticall.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {MulticallTestFacet} from "@lattice-test/helpers/MulticallTestFacet.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {Test} from "forge-std/Test.sol";

/// @title MulticallTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for {Multicall} facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `_deployMulticall` assembles the production {DeployMulticall} recipe (ERC165 + AccessControl +
///         Multicall + {AccessControlInit}) and appends a test-only {MulticallTestFacet} exposing `currentSender`
///         — so every batched call and its `delegatecall` caller-resolution routes through the diamond's dispatch,
///         catching selector/storage/init bugs a mock hides.
abstract contract MulticallTestBase is Test, GetSelectors {
    DeployMulticall internal deployer;
    address internal diamond; // the assembled multicall diamond

    /// @notice Assembles the production multicall diamond with `admin` as the role admin, plus the test facet.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed multicall diamond.
    function _deployMulticall(address admin) internal returns (address diamond_) {
        deployer = new DeployMulticall();
        (FacetCut[] memory prod, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        FacetCut[] memory cuts = new FacetCut[](prod.length + 1);
        for (uint256 i; i < prod.length; ++i) {
            cuts[i] = prod[i];
        }
        cuts[prod.length] = FacetCut({
            facetAddress: address(new MulticallTestFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("MulticallTestFacet")
        });

        LatticeDiamond d = new LatticeDiamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
