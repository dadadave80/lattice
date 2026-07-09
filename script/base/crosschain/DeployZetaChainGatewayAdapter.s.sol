// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ZetaChainGatewayAdapter} from "@lattice/crosschain/ZetaChainGatewayAdapter.sol";
import {ZetaChainGatewayAdapterInit} from "@lattice/crosschain/ZetaChainGatewayAdapterInit.sol";

/// @title DeployZetaChainGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a ZetaChain `GatewayEVM` gateway-adapter diamond: `ERC165Facet` +
///         `AccessControl` + `ZetaChainGatewayAdapter` + {ZetaChainGatewayAdapterInit}. The ONE source of truth
///         for what such an adapter diamond is, shared by production (`run --broadcast`) and the facet tests
///         (which build on {buildCuts}). `AccessControl` is part of the base recipe because the gateway/remote/
///         revert-gas setters are `DEFAULT_ADMIN_ROLE`-gated. The `GatewayEVM` is a DEPLOYED contract (per-
///         connected-chain address), passed as a ctor arg — not a fixed predeploy.
contract DeployZetaChainGatewayAdapter is BaseDeploy {
    /// @notice Builds the adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param gateway The ZetaChain `GatewayEVM` the adapter dispatches to / accepts `onCall` from.
    /// @param hubChainId The hub chainId whose ZEVM universal app terminates the route.
    /// @param hubRemoteApp The trusted ZEVM universal app (hub) for `hubChainId`.
    /// @param defaultOnRevertGasLimit The default `onRevertGasLimit` used to build per-message `RevertOptions`.
    /// @return cuts The facet cuts (ERC165 + AccessControl + ZetaChainGatewayAdapter).
    /// @return init The {ZetaChainGatewayAdapterInit} initializer address.
    /// @return initCalldata The `init(...)` calldata.
    function buildCuts(
        address admin,
        address gateway,
        uint256 hubChainId,
        address hubRemoteApp,
        uint256 defaultOnRevertGasLimit
    ) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new ZetaChainGatewayAdapter()));
        init = address(new ZetaChainGatewayAdapterInit());
        initCalldata = abi.encodeCall(
            ZetaChainGatewayAdapterInit.init, (admin, gateway, hubChainId, hubRemoteApp, defaultOnRevertGasLimit)
        );
    }

    /// @notice Deploys the adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The adapter admin.
    /// @param gateway The ZetaChain `GatewayEVM`.
    /// @param hubChainId The hub chainId.
    /// @param hubRemoteApp The trusted ZEVM universal app (hub).
    /// @param defaultOnRevertGasLimit The default revert gas limit.
    /// @return adapter The deployed adapter diamond address.
    function run(
        address admin,
        address gateway,
        uint256 hubChainId,
        address hubRemoteApp,
        uint256 defaultOnRevertGasLimit
    ) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            buildCuts(admin, gateway, hubChainId, hubRemoteApp, defaultOnRevertGasLimit);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
