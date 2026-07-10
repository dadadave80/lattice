// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployAxelarGatewayAdapter} from "@lattice-script/base/crosschain/DeployAxelarGatewayAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {AxelarGatewayAdapter} from "@lattice/crosschain/AxelarGatewayAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title AxelarGatewayAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for Axelar gateway-adapter facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` assembles the production {DeployAxelarGatewayAdapter} recipe (ERC165 +
///         AccessControl + AxelarGatewayAdapter + {AxelarGatewayAdapterInit}) with the Axelar gateway wired at
///         init, and exposes a typed `adapter` handle — so every send / execute / config call routes through the
///         diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. The external
///         `MockAxelarGateway` and `MockRecipient` stay test fixtures (they are NOT the facet under test).
abstract contract AxelarGatewayAdapterTestBase is Test, GetSelectors {
    DeployAxelarGatewayAdapter internal deployer;
    address internal diamond; // the assembled Axelar adapter diamond
    AxelarGatewayAdapter internal adapter; // typed handle on the diamond (all calls dispatch through it)

    /// @notice Assembles the production Axelar adapter diamond with `admin` as the adapter admin, wiring `gateway`
    ///         at init.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param gateway The Axelar gateway the adapter dispatches to and validates inbound calls with.
    /// @return diamond_ The deployed Axelar adapter diamond.
    function _deployAxelarGatewayAdapter(address admin, address gateway) internal returns (address diamond_) {
        deployer = new DeployAxelarGatewayAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, gateway);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
