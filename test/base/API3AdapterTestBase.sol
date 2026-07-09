// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployAPI3Adapter} from "@lattice-script/base/oracles/DeployAPI3Adapter.s.sol";
import {API3Adapter} from "@lattice/oracles/API3Adapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title API3AdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for API3 adapter facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployAPI3Adapter} recipe (ERC165 + AccessControl + API3Adapter
///         + {API3AdapterInit}) and exposes a typed `adapter` handle — so every feed call routes through the
///         diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. The external
///         `MockApi3Proxy` dAPI reader stays a test fixture (it is NOT the facet under test).
abstract contract API3AdapterTestBase is Test, GetSelectors {
    DeployAPI3Adapter internal deployer;
    address internal diamond; // the assembled API3 adapter diamond
    API3Adapter internal adapter; // typed handle on the diamond (feed calls dispatch through it)

    /// @notice Assembles the production API3 adapter diamond with `admin` as the feed-registry admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed API3 adapter diamond.
    function _deployAPI3Adapter(address admin) internal returns (address diamond_) {
        deployer = new DeployAPI3Adapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
