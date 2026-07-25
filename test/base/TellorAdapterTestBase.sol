// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployTellorAdapter} from "@lattice-script/base/oracles/DeployTellorAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {TellorAdapter} from "@lattice/oracles/tellor/TellorAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title TellorAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for Tellor adapter facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployTellorAdapter} recipe (ERC165 + AccessControl +
///         TellorAdapter + {TellorAdapterInit}) with the external Tellor oracle wired at init, and exposes a typed
///         `adapter` handle — so every read routes through the diamond's `delegatecall` dispatch, catching
///         selector/storage/init bugs a mock hides. The external `MockTellor` stays a test fixture (it is NOT the
///         facet under test). `deployer` is exposed so the zero-address init-revert test can build cuts and drive
///         {Diamond.initialize} directly.
abstract contract TellorAdapterTestBase is Test, GetSelectors {
    DeployTellorAdapter internal deployer;
    address internal diamond; // the assembled Tellor adapter diamond
    TellorAdapter internal adapter; // typed handle on the diamond (reads dispatch through it)

    /// @notice Assembles the production Tellor adapter diamond with `admin` as the feed-registry admin and
    ///         `tellor` as the wired Tellor oracle.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param tellor The Tellor oracle contract the adapter reads reports from.
    /// @return diamond_ The deployed Tellor adapter diamond.
    function _deployTellorAdapter(address admin, address tellor) internal returns (address diamond_) {
        deployer = new DeployTellorAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, tellor);

        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
