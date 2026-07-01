// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployAccessManager} from "@lattice-script/base/DeployAccessManager.s.sol";
import {AccessManager} from "@lattice/access/AccessManager.sol";
import {Test} from "forge-std/Test.sol";

/// @title AccessManagerTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for AccessManager facet tests that exercise a REAL {Diamond}. `setUp` assembles the production
///         {DeployAccessManager} recipe (ERC165 + AccessManager + {AccessManagerInit}) and exposes a typed `mgr`
///         handle — every authority call (roles, targets, schedule/execute/cancel) routes through the diamond's
///         `delegatecall` dispatch. No test-only facet is needed: the AccessManager self-gates its whole surface.
abstract contract AccessManagerTestBase is Test, GetSelectors {
    DeployAccessManager internal deployer;
    address internal diamond; // the assembled AccessManager authority diamond
    AccessManager internal mgr; // typed handle on the diamond

    /// @notice Assembles the production AccessManager diamond with `admin` as the initial admin.
    /// @param admin The address granted the initial `ADMIN_ROLE`.
    /// @return diamond_ The deployed AccessManager diamond.
    function _deployAccessManager(address admin) internal returns (address diamond_) {
        deployer = new DeployAccessManager();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
