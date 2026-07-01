// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployLayerZeroGatewayAdapter} from "@lattice-script/base/DeployLayerZeroGatewayAdapter.s.sol";
import {LayerZeroGatewayAdapter} from "@lattice/crosschain/LayerZeroGatewayAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title LayerZeroGatewayAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for LayerZero gateway-adapter facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` assembles the production {DeployLayerZeroGatewayAdapter} recipe (ERC165 +
///         AccessControl + LayerZeroGatewayAdapter + {LayerZeroGatewayAdapterInit}) with the LayerZero endpoint
///         wired at init, and exposes a typed `adapter` handle — so every send / receive / config call routes
///         through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. The
///         external `MockLayerZeroEndpoint` and `MockRecipient` stay test fixtures (NOT the facet under test).
abstract contract LayerZeroGatewayAdapterTestBase is Test, GetSelectors {
    DeployLayerZeroGatewayAdapter internal deployer;
    address internal diamond; // the assembled LayerZero adapter diamond
    LayerZeroGatewayAdapter internal adapter; // typed handle on the diamond (all calls dispatch through it)

    /// @notice Assembles the production LayerZero adapter diamond with `admin` as the adapter admin, wiring
    ///         `endpoint` at init.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param endpoint The LayerZero v2 EndpointV2 the adapter dispatches to and accepts deliveries from.
    /// @return diamond_ The deployed LayerZero adapter diamond.
    function _deployLayerZeroGatewayAdapter(address admin, address endpoint) internal returns (address diamond_) {
        deployer = new DeployLayerZeroGatewayAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, endpoint);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
