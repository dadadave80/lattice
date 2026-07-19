// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployChainlinkAutomationAdapter} from "@lattice-script/base/oracles/DeployChainlinkAutomationAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {ChainlinkAutomationAdapter} from "@lattice/oracles/chainlink/ChainlinkAutomationAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title ChainlinkAutomationAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ChainlinkAutomationAdapter facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` assembles the production {DeployChainlinkAutomationAdapter} recipe (ERC165 +
///         AccessControl + ChainlinkAutomationAdapter + {ChainlinkAutomationAdapterInit}) and exposes a typed
///         `automation` handle — so every checkUpkeep/performUpkeep/setConfig call routes through the diamond's
///         `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. Admin gating is enforced by
///         the cut-in `AccessControl` facet; `supportsInterface` by the cut-in `ERC165Facet`.
abstract contract ChainlinkAutomationAdapterTestBase is Test, GetSelectors {
    DeployChainlinkAutomationAdapter internal deployer;
    address internal diamond; // the assembled Automation adapter diamond
    ChainlinkAutomationAdapter internal automation; // typed handle on the diamond (calls dispatch through it)

    /// @notice Assembles the production ChainlinkAutomationAdapter diamond with `admin` as the admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed Automation adapter diamond.
    function _deployChainlinkAutomationAdapter(address admin) internal returns (address diamond_) {
        deployer = new DeployChainlinkAutomationAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
