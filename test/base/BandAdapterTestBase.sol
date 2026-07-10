// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployBandAdapter} from "@lattice-script/base/oracles/DeployBandAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {BandAdapter} from "@lattice/oracles/BandAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title BandAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for Band adapter facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployBandAdapter} recipe (ERC165 + AccessControl + BandAdapter
///         + {BandAdapterInit}) with the external StdReference wired at init, and exposes a typed `adapter` handle
///         — so every read routes through the diamond's `delegatecall` dispatch, catching selector/storage/init
///         bugs a mock hides. The external `MockStdReference` stays a test fixture (it is NOT the facet under
///         test). `deployer` is exposed so the zero-reference init-revert test can build cuts and drive
///         {Diamond.initialize} directly.
abstract contract BandAdapterTestBase is Test, GetSelectors {
    DeployBandAdapter internal deployer;
    address internal diamond; // the assembled Band adapter diamond
    BandAdapter internal adapter; // typed handle on the diamond (reads dispatch through it)

    /// @notice Assembles the production Band adapter diamond with `admin` as the feed-registry admin and
    ///         `reference` as the wired Band StdReference.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param reference_ The Band StdReference contract the adapter reads rates from.
    /// @return diamond_ The deployed Band adapter diamond.
    function _deployBandAdapter(address admin, address reference_) internal returns (address diamond_) {
        deployer = new DeployBandAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, reference_);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
