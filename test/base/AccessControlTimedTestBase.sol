// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployAccessControlTimed} from "@lattice-script/base/access/DeployAccessControlTimed.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {AccessControlTimed} from "@lattice/access/AccessControlTimed.sol";
import {Test} from "forge-std/Test.sol";

/// @title AccessControlTimedTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for AccessControlTimed facet tests that exercise a REAL {Diamond}. `setUp` assembles the
///         production {DeployAccessControlTimed} recipe (ERC165 + AccessControlTimed + {AccessControlTimedInit})
///         and exposes a typed `ac` handle — every role + timed-window call routes through the diamond's
///         `delegatecall` dispatch. No test-only facet is needed: the tests drive the public role surface and the
///         timed entrypoints (`grantRoleTimed`/`extendRole`/`roleExpiration`) directly.
abstract contract AccessControlTimedTestBase is Test, GetSelectors {
    DeployAccessControlTimed internal deployer;
    address internal diamond; // the assembled AccessControlTimed diamond
    AccessControlTimed internal ac; // typed handle on the diamond

    /// @notice Assembles the production AccessControlTimed diamond with `admin` as the role admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed AccessControlTimed diamond.
    function _deployAccessControlTimed(address admin) internal returns (address diamond_) {
        deployer = new DeployAccessControlTimed();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        LatticeDiamond d = new LatticeDiamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
