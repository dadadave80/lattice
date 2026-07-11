// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {LayerZeroGatewayAdapter} from "@lattice/crosschain/LayerZeroGatewayAdapter.sol";
import {LayerZeroGatewayAdapterInit} from "@lattice/crosschain/LayerZeroGatewayAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployLayerZeroGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a LayerZero v2 gateway-adapter diamond: `ERC165Facet` + `AccessControl` +
///         `LayerZeroGatewayAdapter` + {LayerZeroGatewayAdapterInit}. The ONE source of truth for what a
///         LayerZero adapter diamond is, shared by production (`run --broadcast`) and the facet tests (which
///         build on {buildCuts}). `AccessControl` is part of the base recipe because every eid / peer /
///         destination setter is `DEFAULT_ADMIN_ROLE`-gated. The LayerZero endpoint is wired at init time.
contract DeployLayerZeroGatewayAdapter is BaseDeploy {
    /// @notice Builds the LayerZero adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param endpoint The LayerZero v2 EndpointV2 the adapter dispatches to and accepts deliveries from.
    /// @return cuts The facet cuts (ERC165 + AccessControl + LayerZeroGatewayAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {LayerZeroGatewayAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address endpoint)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new LayerZeroGatewayAdapter()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new LayerZeroGatewayAdapterInit()),
            abi.encodeCall(LayerZeroGatewayAdapterInit.init, (admin, endpoint))
        );
    }

    /// @notice Deploys a LayerZero adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The adapter admin.
    /// @param endpoint The LayerZero v2 EndpointV2.
    /// @return adapter The deployed LayerZero adapter diamond address.
    function run(address admin, address endpoint) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, endpoint);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
