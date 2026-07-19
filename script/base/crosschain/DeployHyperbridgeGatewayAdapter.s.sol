// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {Receive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {HyperbridgeGatewayAdapter} from "@lattice/crosschain/hyperbridge/HyperbridgeGatewayAdapter.sol";
import {HyperbridgeGatewayAdapterInit} from "@lattice/crosschain/hyperbridge/HyperbridgeGatewayAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployHyperbridgeGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Hyperbridge gateway-adapter diamond: `ERC165Facet` + `AccessControl` +
///         `HyperbridgeGatewayAdapter` + {HyperbridgeGatewayAdapterInit}. The ONE source of truth for what a
///         Hyperbridge adapter diamond is, shared by production (`run --broadcast`) and the facet tests (which
///         build on {buildCuts}). `AccessControl` is part of the base recipe because every state machine /
///         remote-module / timeout setter is `DEFAULT_ADMIN_ROLE`-gated. The Hyperbridge IsmpHost is wired at
///         init time; fees are charged in the host's ERC-20 `feeToken()` read live at send time, so nothing
///         fee-related is deployed here.
contract DeployHyperbridgeGatewayAdapter is BaseDeploy {
    /// @notice Builds the Hyperbridge adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param host  The Hyperbridge IsmpHost the adapter dispatches to and accepts module callbacks from.
    /// @return cuts The facet cuts (ERC165 + AccessControl + HyperbridgeGatewayAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {HyperbridgeGatewayAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address host)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](6);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new HyperbridgeGatewayAdapter()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        cuts[5] = _cut(address(new Receive()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new HyperbridgeGatewayAdapterInit()),
            abi.encodeCall(HyperbridgeGatewayAdapterInit.init, (admin, host))
        );
    }

    /// @notice Deploys a Hyperbridge adapter diamond (broadcasting entrypoint for `forge script ...
    ///         --broadcast`).
    /// @param admin The adapter admin.
    /// @param host  The Hyperbridge IsmpHost.
    /// @return adapter The deployed Hyperbridge adapter diamond address.
    function run(address admin, address host) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, host);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
