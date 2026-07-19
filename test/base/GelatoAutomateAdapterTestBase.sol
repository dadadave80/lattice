// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployGelatoAutomateAdapter} from "@lattice-script/base/oracles/DeployGelatoAutomateAdapter.s.sol";
import {GelatoAutomateAdapterTestFacet} from "@lattice-test/helpers/GelatoAutomateAdapterTestFacet.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {GelatoAutomateAdapter} from "@lattice/oracles/gelato/GelatoAutomateAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title GelatoAutomateAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for GelatoAutomateAdapter facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` assembles the production {DeployGelatoAutomateAdapter} recipe (ERC165 +
///         AccessControl + GelatoAutomateAdapter + {GelatoAutomateAdapterInit}) and APPENDS a test-only
///         {GelatoAutomateAdapterTestFacet} exposing the internal `requireDedicatedMsgSender` exec guard — so
///         every setConfig/createTask/cancelTask call and the gated exec route through the diamond's
///         `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. Admin gating is enforced by
///         the cut-in `AccessControl` facet; `supportsInterface` by the cut-in `ERC165Facet`.
abstract contract GelatoAutomateAdapterTestBase is Test, GetSelectors {
    DeployGelatoAutomateAdapter internal deployer;
    address internal diamond; // the assembled Gelato Automate adapter diamond
    GelatoAutomateAdapter internal gelato; // typed handle on the diamond (calls dispatch through it)
    GelatoAutomateAdapterTestFacet internal execGuard; // typed handle for the test-only exec gate

    /// @notice Assembles the production GelatoAutomateAdapter diamond + the test exec-guard facet with `admin` as
    ///         the admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed Gelato Automate adapter diamond.
    function _deployGelatoAutomateAdapter(address admin) internal returns (address diamond_) {
        deployer = new DeployGelatoAutomateAdapter();
        (FacetCut[] memory prod, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        FacetCut[] memory cuts = new FacetCut[](prod.length + 1);
        for (uint256 i; i < prod.length; ++i) {
            cuts[i] = prod[i];
        }
        cuts[prod.length] = FacetCut({
            facetAddress: address(new GelatoAutomateAdapterTestFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("GelatoAutomateAdapterTestFacet")
        });

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
