// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ChainlinkAdapter} from "@lattice/oracles/ChainlinkAdapter.sol";
import {ChainlinkAdapterInit} from "@lattice/oracles/ChainlinkAdapterInit.sol";

/// @title DeployChainlinkAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Chainlink price-feed adapter diamond: `ERC165Facet` + `AccessControl` +
///         `ChainlinkAdapter` + {ChainlinkAdapterInit}. The ONE source of truth for what a Chainlink adapter
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because every feed-registry setter is
///         `DEFAULT_ADMIN_ROLE`-gated.
contract DeployChainlinkAdapter is BaseDeploy {
    /// @notice Builds the Chainlink adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the feed registry).
    /// @return cuts The facet cuts (ERC165 + AccessControl + ChainlinkAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {ChainlinkAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new ChainlinkAdapter()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new ChainlinkAdapterInit()), abi.encodeCall(ChainlinkAdapterInit.init, (admin))
        );
    }

    /// @notice Deploys a Chainlink adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The feed-registry admin.
    /// @return adapter The deployed Chainlink adapter diamond address.
    function run(address admin) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
