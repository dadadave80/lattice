// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployPythAdapter} from "@lattice-script/base/oracles/DeployPythAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {PythAdapter} from "@lattice/oracles/pyth/PythAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title PythAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for Pyth adapter facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployPythAdapter} recipe (ERC165 + AccessControl + PythAdapter
///         + {PythAdapterInit}) with the external Pyth reference wired at init, and exposes a typed `adapter`
///         handle — so every read and the payable `updatePriceFeeds` fee-forwarding path route through the
///         diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. The external
///         `MockPyth` stays a test fixture (it is NOT the facet under test).
abstract contract PythAdapterTestBase is Test, GetSelectors {
    DeployPythAdapter internal deployer;
    address internal diamond; // the assembled Pyth adapter diamond
    PythAdapter internal adapter; // typed handle on the diamond (reads + update path dispatch through it)

    /// @notice Assembles the production Pyth adapter diamond with `admin` as the feed-registry admin and `pyth`
    ///         as the wired Pyth contract reference.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param pyth The Pyth contract the adapter reads prices from and forwards update fees to.
    /// @return diamond_ The deployed Pyth adapter diamond.
    function _deployPythAdapter(address admin, address pyth) internal returns (address diamond_) {
        deployer = new DeployPythAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, pyth);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
