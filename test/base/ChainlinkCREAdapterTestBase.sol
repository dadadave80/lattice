// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployChainlinkCREAdapter} from "@lattice-script/base/DeployChainlinkCREAdapter.s.sol";
import {ChainlinkCREAdapter} from "@lattice/oracles/ChainlinkCREAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title ChainlinkCREAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ChainlinkCREAdapter facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` assembles the production {DeployChainlinkCREAdapter} recipe (ERC165 +
///         AccessControl + ChainlinkCREAdapter + {ChainlinkCREAdapterInit}) and exposes a typed `cre` handle — so
///         every onReport/setForwarder/setWorkflow call routes through the diamond's `delegatecall` dispatch,
///         catching selector/storage/init bugs a mock hides. Admin gating is enforced by the cut-in
///         `AccessControl` facet; `supportsInterface` (canonical IReceiver id) by the cut-in `ERC165Facet`.
abstract contract ChainlinkCREAdapterTestBase is Test, GetSelectors {
    DeployChainlinkCREAdapter internal deployer;
    address internal diamond; // the assembled CRE adapter diamond
    ChainlinkCREAdapter internal cre; // typed handle on the diamond (calls dispatch through it)

    /// @notice Assembles the production ChainlinkCREAdapter diamond with `admin` as the admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed CRE adapter diamond.
    function _deployChainlinkCREAdapter(address admin) internal returns (address diamond_) {
        deployer = new DeployChainlinkCREAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
