// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployDIAAdapter} from "@lattice-script/base/oracles/DeployDIAAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {DIAAdapter} from "@lattice/oracles/DIAAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title DIAAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for DIA adapter facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployDIAAdapter} recipe (ERC165 + AccessControl + DIAAdapter +
///         {DIAAdapterInit}) and exposes a typed `adapter` handle — so every feed call routes through the
///         diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. The external
///         `MockDIAOracle` stays a test fixture (it is NOT the facet under test).
abstract contract DIAAdapterTestBase is Test, GetSelectors {
    DeployDIAAdapter internal deployer;
    address internal diamond; // the assembled DIA adapter diamond
    DIAAdapter internal adapter; // typed handle on the diamond (feed calls dispatch through it)

    /// @notice Assembles the production DIA adapter diamond with `admin` as the feed-registry admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed DIA adapter diamond.
    function _deployDIAAdapter(address admin) internal returns (address diamond_) {
        deployer = new DeployDIAAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
