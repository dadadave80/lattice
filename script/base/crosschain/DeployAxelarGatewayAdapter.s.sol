// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {Receive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AxelarGatewayAdapter} from "@lattice/crosschain/axelar/AxelarGatewayAdapter.sol";
import {AxelarGatewayAdapterInit} from "@lattice/crosschain/axelar/AxelarGatewayAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployAxelarGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an Axelar gateway-adapter diamond: `ERC165Facet` + `AccessControl` +
///         `AxelarGatewayAdapter` + {AxelarGatewayAdapterInit}. The ONE source of truth for what an Axelar adapter
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because every chain-equivalence / remote-gateway setter is
///         `DEFAULT_ADMIN_ROLE`-gated. The Axelar gateway is wired at init time.
contract DeployAxelarGatewayAdapter is BaseDeploy {
    /// @notice Builds the Axelar adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param gateway The Axelar gateway the adapter dispatches to and validates inbound calls with.
    /// @return cuts The facet cuts (ERC165 + AccessControl + AxelarGatewayAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {AxelarGatewayAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address gateway)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](6);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new AxelarGatewayAdapter()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        cuts[5] = _cut(address(new Receive()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new AxelarGatewayAdapterInit()), abi.encodeCall(AxelarGatewayAdapterInit.init, (admin, gateway))
        );
    }

    /// @notice Deploys an Axelar adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The adapter admin.
    /// @param gateway The Axelar gateway.
    /// @return adapter The deployed Axelar adapter diamond address.
    function run(address admin, address gateway) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, gateway);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
