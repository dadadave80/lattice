// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {Receive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {TellorAdapter} from "@lattice/oracles/tellor/TellorAdapter.sol";
import {TellorAdapterInit} from "@lattice/oracles/tellor/TellorAdapterInit.sol";

/// @title DeployTellorAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Tellor price-feed adapter diamond: `ERC165Facet` + `AccessControl` +
///         `TellorAdapter` + {TellorAdapterInit}. The ONE source of truth for what a Tellor adapter diamond is,
///         shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because the feed-registry setters and `setTellor` are
///         `DEFAULT_ADMIN_ROLE`-gated. Unlike the registry-only adapters, the Tellor oracle is wired at init.
contract DeployTellorAdapter is BaseDeploy {
    /// @notice Builds the Tellor adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the feed registry and `setTellor`).
    /// @param tellor The Tellor oracle contract the adapter reads reports from (reverts if zero).
    /// @return cuts The facet cuts (ERC165 + AccessControl + TellorAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {TellorAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address tellor)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](6);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new TellorAdapter()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        cuts[5] = _cut(address(new Receive()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new TellorAdapterInit()), abi.encodeCall(TellorAdapterInit.init, (admin, tellor))
        );
    }

    /// @notice Deploys a Tellor adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The feed-registry admin.
    /// @param tellor The Tellor oracle contract reference.
    /// @return adapter The deployed Tellor adapter diamond address.
    function run(address admin, address tellor) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, tellor);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
