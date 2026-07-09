// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployHyperbridgeGatewayAdapter} from "@lattice-script/base/crosschain/DeployHyperbridgeGatewayAdapter.s.sol";
import {HyperbridgeGatewayAdapter} from "@lattice/crosschain/HyperbridgeGatewayAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title HyperbridgeGatewayAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for Hyperbridge gateway-adapter facet tests that exercise a REAL {Diamond} rather than a
///         flattened inheritance mock. `setUp` assembles the production {DeployHyperbridgeGatewayAdapter}
///         recipe (ERC165 + AccessControl + HyperbridgeGatewayAdapter + {HyperbridgeGatewayAdapterInit}) with
///         the Hyperbridge IsmpHost wired at init, and exposes a typed `adapter` handle — so every send /
///         receive / config call routes through the diamond's `delegatecall` dispatch, catching
///         selector/storage/init bugs a mock hides. The external {MockIsmpHost} and fee-token/recipient mocks
///         stay test fixtures (NOT the facet under test).
abstract contract HyperbridgeGatewayAdapterTestBase is Test, GetSelectors {
    DeployHyperbridgeGatewayAdapter internal deployer;
    address internal diamond; // the assembled Hyperbridge adapter diamond
    HyperbridgeGatewayAdapter internal adapter; // typed handle on the diamond (all calls dispatch through it)

    /// @notice Assembles the production Hyperbridge adapter diamond with `admin` as the adapter admin, wiring
    ///         `host` at init.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param host  The Hyperbridge IsmpHost the adapter dispatches to and accepts module callbacks from.
    /// @return diamond_ The deployed Hyperbridge adapter diamond.
    function _deployHyperbridgeGatewayAdapter(address admin, address host) internal returns (address diamond_) {
        deployer = new DeployHyperbridgeGatewayAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, host);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
