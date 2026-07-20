// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {Receive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {SuperchainETHBridgeAdapter} from "@lattice/crosschain/optimism/SuperchainETHBridgeAdapter.sol";
import {SuperchainETHBridgeAdapterInit} from "@lattice/crosschain/optimism/SuperchainETHBridgeAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeploySuperchainETHBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a `SuperchainETHBridge` interop adapter diamond: `ERC165Facet` +
///         `SuperchainETHBridgeAdapter` + {SuperchainETHBridgeAdapterInit}. The ONE source of truth for what the
///         adapter diamond is, shared by production (`run --broadcast`) and the facet tests (via {buildCuts}).
///         No `AccessControl` in the recipe: the adapter has no admin surface (the predeploy is a compile-time
///         constant and there is no config to gate).
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut; deploy a new diamond to change
///      behavior. Use the ADMIN overload (`buildCuts(..., admin)` / `run(..., admin)`) for an upgradeable
///      deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeploySuperchainETHBridgeAdapter is BaseDeploy {
    /// @notice Builds the adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @return cuts         The facet cuts (ERC165 + SuperchainETHBridgeAdapter).
    /// @return init         The {MultiInit} running {SuperchainETHBridgeAdapterInit} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts() public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _coreCuts();
        (init, initCalldata) = _withImmutableIntrospection(
            address(new SuperchainETHBridgeAdapterInit()), abi.encodeCall(SuperchainETHBridgeAdapterInit.init, ())
        );
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        FacetCut[] memory base = _coreCuts();
        cuts = new FacetCut[](base.length + 2);
        for (uint256 i; i < base.length; ++i) {
            cuts[i] = base[i];
        }
        cuts[base.length] = _cut(address(new AccessControl()));
        cuts[base.length + 1] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withAdminUpgradeableIntrospection(
            address(new SuperchainETHBridgeAdapterInit()),
            abi.encodeCall(SuperchainETHBridgeAdapterInit.init, ()),
            admin
        );
    }

    /// @dev The shared cut set of both overloads: the module facets plus {DiamondLoupeFacet} (introspection).
    function _coreCuts() internal returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](4);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new SuperchainETHBridgeAdapter()));
        cuts[2] = _cut(address(new DiamondLoupeFacet()));
        cuts[3] = _cut(address(new Receive()));
    }

    /// @notice Deploys a `SuperchainETHBridge` adapter diamond (broadcasting entrypoint for `forge script`).
    /// @return adapter The deployed adapter diamond address.
    function run() external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts();
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(address admin) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
