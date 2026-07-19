// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployAPI3QRNGAdapter} from "@lattice-script/base/oracles/DeployAPI3QRNGAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {API3QRNGAdapter} from "@lattice/oracles/api3/API3QRNGAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title API3QRNGAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for API3 QRNG facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployAPI3QRNGAdapter} recipe (ERC165 + AccessControl +
///         API3QRNGAdapter + {API3QRNGAdapterInit}) and exposes a typed `qrng` handle — so every QRNG call
///         routes through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock
///         hides. Admin gating is enforced by the cut-in `AccessControl` facet; `supportsInterface` by
///         `ERC165Facet`.
abstract contract API3QRNGAdapterTestBase is Test, GetSelectors {
    DeployAPI3QRNGAdapter internal deployer;
    address internal diamond; // the assembled QRNG diamond
    API3QRNGAdapter internal qrng; // typed handle on the diamond (QRNG calls dispatch through it)

    /// @notice Assembles the production API3 QRNG diamond with `admin` as the QRNG admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed QRNG diamond.
    function _deployAPI3QRNGAdapter(address admin) internal returns (address diamond_) {
        deployer = new DeployAPI3QRNGAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
