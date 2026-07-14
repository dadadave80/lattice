// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployCCIPGatewayAdapter} from "@lattice-script/base/crosschain/DeployCCIPGatewayAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {CCIPGatewayAdapter} from "@lattice/crosschain/CCIPGatewayAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title CCIPGatewayAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for CCIP gateway-adapter facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` assembles the production {DeployCCIPGatewayAdapter} recipe (ERC165 +
///         AccessControl + CCIPGatewayAdapter + {CCIPGatewayAdapterInit}) with the CCIP router + fee token wired at
///         init, and exposes a typed `adapter` handle — so every send / receive / config call routes through the
///         diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. The external
///         `MockCCIPRouter`, `MockERC20` and `MockRecipient` stay test fixtures (they are NOT the facet under test).
abstract contract CCIPGatewayAdapterTestBase is Test, GetSelectors {
    DeployCCIPGatewayAdapter internal deployer;
    address internal diamond; // the assembled CCIP adapter diamond
    CCIPGatewayAdapter internal adapter; // typed handle on the diamond (all calls dispatch through it)

    /// @notice Assembles the production CCIP adapter diamond with `admin` as the adapter admin, wiring `router`
    ///         and `feeToken` at init.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param router The CCIP router the adapter dispatches to and accepts deliveries from.
    /// @param feeToken The initial CCIP fee token (`address(0)` = native gas).
    /// @return diamond_ The deployed CCIP adapter diamond.
    function _deployCCIPGatewayAdapter(address admin, address router, address feeToken)
        internal
        returns (address diamond_)
    {
        deployer = new DeployCCIPGatewayAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, router, feeToken);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
