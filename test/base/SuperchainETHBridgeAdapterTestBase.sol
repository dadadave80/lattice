// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeploySuperchainETHBridgeAdapter} from "@lattice-script/base/crosschain/DeploySuperchainETHBridgeAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {Test} from "forge-std/Test.sol";

/// @title SuperchainETHBridgeAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for `SuperchainETHBridge` adapter facet tests that exercise a REAL {Diamond} rather than a
///         flattened inheritance mock. `_deploySuperchainETHBridgeAdapter` assembles the production
///         {DeploySuperchainETHBridgeAdapter} recipe (ERC165 + SuperchainETHBridgeAdapter + Init) so every
///         `sendETH` / `bridge` call routes through the diamond's `delegatecall` dispatch, catching
///         selector/init bugs a mock hides.
abstract contract SuperchainETHBridgeAdapterTestBase is Test, GetSelectors {
    DeploySuperchainETHBridgeAdapter internal deployer;

    /// @notice Assembles the production `SuperchainETHBridge` adapter diamond.
    /// @return diamond_ The deployed adapter diamond.
    function _deploySuperchainETHBridgeAdapter() internal returns (address diamond_) {
        deployer = new DeploySuperchainETHBridgeAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts();

        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
