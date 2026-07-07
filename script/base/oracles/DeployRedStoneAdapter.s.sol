// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {RedStoneAdapter} from "@lattice/oracles/RedStoneAdapter.sol";
import {RedStoneAdapterInit} from "@lattice/oracles/RedStoneAdapterInit.sol";

/// @title DeployRedStoneAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a RedStone Push price-feed adapter diamond: `ERC165Facet` + `AccessControl` +
///         `RedStoneAdapter` + {RedStoneAdapterInit}. The ONE source of truth for what a RedStone adapter diamond
///         is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because every feed-registry setter is
///         `DEFAULT_ADMIN_ROLE`-gated.
contract DeployRedStoneAdapter is BaseDeploy {
    /// @notice Builds the RedStone adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the feed registry).
    /// @return cuts The facet cuts (ERC165 + AccessControl + RedStoneAdapter).
    /// @return init The {RedStoneAdapterInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new RedStoneAdapter()), "RedStoneAdapter");
        init = address(new RedStoneAdapterInit());
        initCalldata = abi.encodeCall(RedStoneAdapterInit.init, (admin));
    }

    /// @notice Deploys a RedStone adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The feed-registry admin.
    /// @return adapter The deployed RedStone adapter diamond address.
    function run(address admin) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
