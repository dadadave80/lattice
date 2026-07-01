// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployAccessControl} from "@lattice-script/base/DeployAccessControl.s.sol";
import {AccessControlTestFacet} from "@lattice-test/helpers/AccessControlTestFacet.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {Test} from "forge-std/Test.sol";

/// @title AccessControlTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for AccessControl facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployAccessControl} recipe (ERC165 + AccessControl +
///         {AccessControlInit}) and appends a test-only {AccessControlTestFacet} for the internal `setRoleAdmin`
///         and `onlyRole` gate — so every role call routes through the diamond's `delegatecall` dispatch,
///         catching selector/storage/init bugs a mock hides.
abstract contract AccessControlTestBase is Test, GetSelectors {
    DeployAccessControl internal deployer;
    address internal diamond; // the assembled AccessControl diamond
    AccessControl internal accessControl; // typed handle on the diamond (role calls dispatch through it)
    AccessControlTestFacet internal helper; // typed handle for the test-only setRoleAdmin / restrictedFunction

    /// @notice Assembles the production AccessControl diamond with `admin` as the role admin, plus the test facet.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed AccessControl diamond.
    function _deployAccessControl(address admin) internal returns (address diamond_) {
        deployer = new DeployAccessControl();
        (FacetCut[] memory prod, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        FacetCut[] memory cuts = new FacetCut[](prod.length + 1);
        for (uint256 i; i < prod.length; ++i) {
            cuts[i] = prod[i];
        }
        cuts[prod.length] = FacetCut({
            facetAddress: address(new AccessControlTestFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("AccessControlTestFacet")
        });

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
