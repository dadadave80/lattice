// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {Receive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {WormholeGatewayAdapter} from "@lattice/crosschain/wormhole/WormholeGatewayAdapter.sol";
import {WormholeGatewayAdapterInit} from "@lattice/crosschain/wormhole/WormholeGatewayAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployWormholeGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Wormhole gateway-adapter diamond: `ERC165Facet` + `AccessControl` +
///         `WormholeGatewayAdapter` + {WormholeGatewayAdapterInit}. The ONE source of truth for what a Wormhole
///         adapter diamond is, shared by production (`run --broadcast`) and the facet tests (which build on
///         {buildCuts}). `AccessControl` is part of the base recipe because every chain-equivalence /
///         remote-gateway setter is `DEFAULT_ADMIN_ROLE`-gated. The Wormhole relayer and this chain's Wormhole
///         chain id are wired at init time.
contract DeployWormholeGatewayAdapter is BaseDeploy {
    /// @notice Builds the Wormhole adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param relayer The Wormhole relayer the adapter dispatches to and accepts deliveries from.
    /// @param wormholeChainId This chain's Wormhole chain id.
    /// @return cuts The facet cuts (ERC165 + AccessControl + WormholeGatewayAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {WormholeGatewayAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address relayer, uint16 wormholeChainId)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](6);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new WormholeGatewayAdapter()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        cuts[5] = _cut(address(new Receive()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new WormholeGatewayAdapterInit()),
            abi.encodeCall(WormholeGatewayAdapterInit.init, (admin, relayer, wormholeChainId))
        );
    }

    /// @notice Deploys a Wormhole adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The adapter admin.
    /// @param relayer The Wormhole relayer.
    /// @param wormholeChainId This chain's Wormhole chain id.
    /// @return adapter The deployed Wormhole adapter diamond address.
    function run(address admin, address relayer, uint16 wormholeChainId) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, relayer, wormholeChainId);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
