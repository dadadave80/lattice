// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployHyperlaneGatewayAdapter} from "@lattice-script/base/crosschain/DeployHyperlaneGatewayAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {HyperlaneGatewayAdapter} from "@lattice/crosschain/hyperlane/HyperlaneGatewayAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title HyperlaneGatewayAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for Hyperlane gateway-adapter facet tests that exercise a REAL {Diamond} rather than a
///         flattened inheritance mock. `setUp` assembles the production {DeployHyperlaneGatewayAdapter} recipe
///         (ERC165 + AccessControl + HyperlaneGatewayAdapter + {HyperlaneGatewayAdapterInit}) with the
///         Hyperlane Mailbox wired at init, and exposes a typed `adapter` handle — so every send / receive /
///         config call routes through the diamond's `delegatecall` dispatch, catching selector/storage/init
///         bugs a mock hides. The external {MockMailbox} and `MockRecipient` stay test fixtures (NOT the facet
///         under test).
abstract contract HyperlaneGatewayAdapterTestBase is Test, GetSelectors {
    DeployHyperlaneGatewayAdapter internal deployer;
    address internal diamond; // the assembled Hyperlane adapter diamond
    HyperlaneGatewayAdapter internal adapter; // typed handle on the diamond (all calls dispatch through it)

    /// @notice Assembles the production Hyperlane adapter diamond with `admin` as the adapter admin, wiring
    ///         `mailbox` at init.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param mailbox The Hyperlane Mailbox the adapter dispatches to and accepts deliveries from.
    /// @return diamond_ The deployed Hyperlane adapter diamond.
    function _deployHyperlaneGatewayAdapter(address admin, address mailbox) internal returns (address diamond_) {
        deployer = new DeployHyperlaneGatewayAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, mailbox);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
