// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {BandAdapter} from "@lattice/oracles/BandAdapter.sol";
import {BandAdapterInit} from "@lattice/oracles/BandAdapterInit.sol";

/// @title DeployBandAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Band price-feed adapter diamond: `ERC165Facet` + `AccessControl` +
///         `BandAdapter` + {BandAdapterInit}. The ONE source of truth for what a Band adapter diamond is, shared
///         by production (`run --broadcast`) and the facet tests (which build on {buildCuts}). `AccessControl` is
///         part of the base recipe because the feed-registry setters and `setReference` are
///         `DEFAULT_ADMIN_ROLE`-gated. Unlike the registry-only adapters, the Band StdReference is wired at init.
contract DeployBandAdapter is BaseDeploy {
    /// @notice Builds the Band adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the feed registry and `setReference`).
    /// @param reference_ The Band StdReference contract the adapter reads rates from (reverts if zero).
    /// @return cuts The facet cuts (ERC165 + AccessControl + BandAdapter).
    /// @return init The {BandAdapterInit} initializer address.
    /// @return initCalldata The `init(admin, reference)` calldata.
    function buildCuts(address admin, address reference_)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new BandAdapter()), "BandAdapter");
        init = address(new BandAdapterInit());
        initCalldata = abi.encodeCall(BandAdapterInit.init, (admin, reference_));
    }

    /// @notice Deploys a Band adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The feed-registry admin.
    /// @param reference_ The Band StdReference contract reference.
    /// @return adapter The deployed Band adapter diamond address.
    function run(address admin, address reference_) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, reference_);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
