// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployGelatoVRFAdapter} from "@lattice-script/base/oracles/DeployGelatoVRFAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {GelatoVRFAdapter} from "@lattice/oracles/gelato/GelatoVRFAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title GelatoVRFAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for Gelato VRF facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployGelatoVRFAdapter} recipe (ERC165 + AccessControl +
///         GelatoVRFAdapter + {GelatoVRFAdapterInit}) and exposes a typed `adapter` handle — so every Gelato VRF
///         call routes through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock
///         hides. Admin gating is enforced by the cut-in `AccessControl` facet; `supportsInterface` by
///         `ERC165Facet`.
abstract contract GelatoVRFAdapterTestBase is Test, GetSelectors {
    DeployGelatoVRFAdapter internal deployer;
    address internal diamond; // the assembled Gelato VRF diamond
    GelatoVRFAdapter internal adapter; // typed handle on the diamond (Gelato VRF calls dispatch through it)

    /// @notice Assembles the production Gelato VRF diamond with `admin` as the Gelato VRF admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed Gelato VRF diamond.
    function _deployGelatoVRFAdapter(address admin) internal returns (address diamond_) {
        deployer = new DeployGelatoVRFAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
