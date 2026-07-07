// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AggregatorExecAdapter} from "@lattice/defi/AggregatorExecAdapter.sol";
import {AggregatorExecAdapterInit} from "@lattice/defi/AggregatorExecAdapterInit.sol";

/// @title DeployAggregatorExecAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a generic swap/bridge execution diamond: `ERC165Facet` + `AccessControl` +
///         `AggregatorExecAdapter` + {AggregatorExecAdapterInit}. The ONE source of truth for what an aggregator
///         execution diamond is, shared by production (`run --broadcast`) and the facet tests (which build on
///         {buildCuts}). `AccessControl` is part of the base recipe because the `(aggregator, selector)`
///         allow-list setter is `DEFAULT_ADMIN_ROLE`-gated. The aggregator allow-list is populated by the admin
///         AFTER deploy (e.g. allow-listing the LI.FI Diamond's swap/bridge selectors).
contract DeployAggregatorExecAdapter is BaseDeploy {
    /// @notice Builds the aggregator execution diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the allow-list setter).
    /// @return cuts         The facet cuts (ERC165 + AccessControl + AggregatorExecAdapter).
    /// @return init         The {AggregatorExecAdapterInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new AggregatorExecAdapter()), "AggregatorExecAdapter");
        init = address(new AggregatorExecAdapterInit());
        initCalldata = abi.encodeCall(AggregatorExecAdapterInit.init, (admin));
    }

    /// @notice Deploys an aggregator execution diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The adapter admin.
    /// @return adapter The deployed aggregator execution diamond address.
    function run(address admin) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
