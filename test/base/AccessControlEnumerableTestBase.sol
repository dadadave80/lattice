// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployAccessControlEnumerable} from "@lattice-script/base/DeployAccessControlEnumerable.s.sol";
import {AccessControlEnumerable} from "@lattice/access/AccessControlEnumerable.sol";
import {Test} from "forge-std/Test.sol";

/// @title AccessControlEnumerableTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for AccessControlEnumerable facet tests that exercise a REAL {Diamond}. `setUp` assembles the
///         production {DeployAccessControlEnumerable} recipe (ERC165 + AccessControlEnumerable +
///         {AccessControlEnumerableInit}) and exposes a typed `ac` handle — every role + enumeration call routes
///         through the diamond's `delegatecall` dispatch. No test-only facet is needed: the tests drive the
///         public role surface and the enumeration getters directly.
abstract contract AccessControlEnumerableTestBase is Test, GetSelectors {
    DeployAccessControlEnumerable internal deployer;
    address internal diamond; // the assembled AccessControlEnumerable diamond
    AccessControlEnumerable internal ac; // typed handle on the diamond

    /// @notice Assembles the production AccessControlEnumerable diamond with `admin` as the role admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed AccessControlEnumerable diamond.
    function _deployAccessControlEnumerable(address admin) internal returns (address diamond_) {
        deployer = new DeployAccessControlEnumerable();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
