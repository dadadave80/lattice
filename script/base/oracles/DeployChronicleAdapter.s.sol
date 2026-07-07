// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ChronicleAdapter} from "@lattice/oracles/ChronicleAdapter.sol";
import {ChronicleAdapterInit} from "@lattice/oracles/ChronicleAdapterInit.sol";

/// @title DeployChronicleAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Chronicle price-feed adapter diamond: `ERC165Facet` + `AccessControl` +
///         `ChronicleAdapter` + {ChronicleAdapterInit}. The ONE source of truth for what a Chronicle adapter
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because every feed-registry setter is
///         `DEFAULT_ADMIN_ROLE`-gated.
contract DeployChronicleAdapter is BaseDeploy {
    /// @notice Builds the Chronicle adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the feed registry).
    /// @return cuts The facet cuts (ERC165 + AccessControl + ChronicleAdapter).
    /// @return init The {ChronicleAdapterInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new ChronicleAdapter()), "ChronicleAdapter");
        init = address(new ChronicleAdapterInit());
        initCalldata = abi.encodeCall(ChronicleAdapterInit.init, (admin));
    }

    /// @notice Deploys a Chronicle adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The feed-registry admin.
    /// @return adapter The deployed Chronicle adapter diamond address.
    function run(address admin) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
