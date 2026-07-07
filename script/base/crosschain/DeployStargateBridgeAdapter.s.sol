// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {StargateBridgeAdapter} from "@lattice/crosschain/StargateBridgeAdapter.sol";
import {StargateBridgeAdapterInit} from "@lattice/crosschain/StargateBridgeAdapterInit.sol";

/// @title DeployStargateBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Stargate v2 token-bridge diamond: `ERC165Facet` + `AccessControl` +
///         `StargateBridgeAdapter` + {StargateBridgeAdapterInit}. The ONE source of truth for what a Stargate
///         adapter diamond is, shared by production (`run --broadcast`) and the facet tests (which build on
///         {buildCuts}). `AccessControl` is part of the base recipe because every eid / pool registration is
///         `DEFAULT_ADMIN_ROLE`-gated. No protocol addresses are wired at init: the chainId ⇄ eid map and the
///         per-token pools (ERC-20 pools ONLY — never `StargatePoolNative`) are registered by the admin AFTER
///         deploy (verify them).
contract DeployStargateBridgeAdapter is BaseDeploy {
    /// @notice Builds the Stargate adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @return cuts         The facet cuts (ERC165 + AccessControl + StargateBridgeAdapter).
    /// @return init         The {StargateBridgeAdapterInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new StargateBridgeAdapter()), "StargateBridgeAdapter");
        init = address(new StargateBridgeAdapterInit());
        initCalldata = abi.encodeCall(StargateBridgeAdapterInit.init, (admin));
    }

    /// @notice Deploys a Stargate adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The adapter admin.
    /// @return adapter The deployed Stargate adapter diamond address.
    function run(address admin) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
