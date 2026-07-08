// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {SuperchainETHBridgeAdapter} from "@lattice/crosschain/SuperchainETHBridgeAdapter.sol";
import {SuperchainETHBridgeAdapterInit} from "@lattice/crosschain/SuperchainETHBridgeAdapterInit.sol";

/// @title DeploySuperchainETHBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a `SuperchainETHBridge` interop adapter diamond: `ERC165Facet` +
///         `SuperchainETHBridgeAdapter` + {SuperchainETHBridgeAdapterInit}. The ONE source of truth for what the
///         adapter diamond is, shared by production (`run --broadcast`) and the facet tests (via {buildCuts}).
///         No `AccessControl` in the recipe: the adapter has no admin surface (the predeploy is a compile-time
///         constant and there is no config to gate).
contract DeploySuperchainETHBridgeAdapter is BaseDeploy {
    /// @notice Builds the adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @return cuts         The facet cuts (ERC165 + SuperchainETHBridgeAdapter).
    /// @return init         The {SuperchainETHBridgeAdapterInit} initializer address.
    /// @return initCalldata The `init()` calldata.
    function buildCuts() public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](2);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new SuperchainETHBridgeAdapter()));
        init = address(new SuperchainETHBridgeAdapterInit());
        initCalldata = abi.encodeCall(SuperchainETHBridgeAdapterInit.init, ());
    }

    /// @notice Deploys a `SuperchainETHBridge` adapter diamond (broadcasting entrypoint for `forge script`).
    /// @return adapter The deployed adapter diamond address.
    function run() external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts();
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
