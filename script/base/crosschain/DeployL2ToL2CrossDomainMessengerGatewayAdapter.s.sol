// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {
    L2ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice/crosschain/L2ToL2CrossDomainMessengerGatewayAdapter.sol";
import {
    L2ToL2CrossDomainMessengerGatewayAdapterInit
} from "@lattice/crosschain/L2ToL2CrossDomainMessengerGatewayAdapterInit.sol";

/// @title DeployL2ToL2CrossDomainMessengerGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an OP Superchain `L2ToL2CrossDomainMessenger` gateway-adapter diamond:
///         `ERC165Facet` + `AccessControl` + `L2ToL2CrossDomainMessengerGatewayAdapter` +
///         {L2ToL2CrossDomainMessengerGatewayAdapterInit}. The ONE source of truth for what such an adapter
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because the remote-adapter setter is
///         `DEFAULT_ADMIN_ROLE`-gated. Unlike the CCIP/LayerZero recipes there is no endpoint/router arg — the
///         messenger is the fixed predeploy constant.
contract DeployL2ToL2CrossDomainMessengerGatewayAdapter is BaseDeploy {
    /// @notice Builds the adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the remote-adapter setter).
    /// @return cuts The facet cuts (ERC165 + AccessControl + L2ToL2CrossDomainMessengerGatewayAdapter).
    /// @return init The {L2ToL2CrossDomainMessengerGatewayAdapterInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new L2ToL2CrossDomainMessengerGatewayAdapter()));
        init = address(new L2ToL2CrossDomainMessengerGatewayAdapterInit());
        initCalldata = abi.encodeCall(L2ToL2CrossDomainMessengerGatewayAdapterInit.init, (admin));
    }

    /// @notice Deploys the adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The adapter admin.
    /// @return adapter The deployed adapter diamond address.
    function run(address admin) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
