// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployEmergencyStop} from "@lattice-script/base/DeployEmergencyStop.s.sol";
import {EmergencyStopTestFacet} from "@lattice-test/helpers/EmergencyStopTestFacet.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";
import {Test} from "forge-std/Test.sol";

/// @title EmergencyStopTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for EmergencyStop facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployEmergencyStop} recipe (ERC165 + AccessControl +
///         EmergencyStop + {EmergencyStopInit}) and APPENDS a test-only {EmergencyStopTestFacet} exposing the
///         internal `checkNotStopped` consumer guard — so every stop/resume call and every gated action routes
///         through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides.
abstract contract EmergencyStopTestBase is Test, GetSelectors {
    DeployEmergencyStop internal deployer;
    address internal diamond; // the assembled emergency-stop diamond
    EmergencyStop internal emergency; // typed handle on the diamond (stop/resume calls dispatch through it)
    EmergencyStopTestFacet internal guard; // typed handle for the test-only checkNotStopped gate

    /// @notice Assembles the production EmergencyStop diamond + the test guard facet with `admin` as the admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed emergency-stop diamond.
    function _deployEmergencyStop(address admin) internal returns (address diamond_) {
        deployer = new DeployEmergencyStop();
        (FacetCut[] memory prod, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        FacetCut[] memory cuts = new FacetCut[](prod.length + 1);
        for (uint256 i; i < prod.length; ++i) {
            cuts[i] = prod[i];
        }
        cuts[prod.length] = FacetCut({
            facetAddress: address(new EmergencyStopTestFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("EmergencyStopTestFacet")
        });

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
