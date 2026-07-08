// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {CCTPBridgeAdapter} from "@lattice/crosschain/CCTPBridgeAdapter.sol";
import {CCTPBridgeAdapterInit} from "@lattice/crosschain/CCTPBridgeAdapterInit.sol";

/// @title DeployCCTPBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Circle CCTP v2 USDC token-bridge diamond: `ERC165Facet` +
///         `AccessControl` + `CCTPBridgeAdapter` + {CCTPBridgeAdapterInit}. The ONE source of truth for what a
///         CCTP adapter diamond is, shared by production (`run --broadcast`) and the facet tests (which build
///         on {buildCuts}). `AccessControl` is part of the base recipe because every chain-domain / per-domain
///         config setter is `DEFAULT_ADMIN_ROLE`-gated. The CCTP TokenMessenger, MessageTransmitter and USDC
///         are wired at init time; the CCTP domain table is registered by the admin AFTER deploy (verify it).
contract DeployCCTPBridgeAdapter is BaseDeploy {
    /// @notice Builds the CCTP adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin              The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param tokenMessenger     The deployed CCTP v2 `TokenMessengerV2`.
    /// @param messageTransmitter The deployed CCTP v2 `MessageTransmitterV2`.
    /// @param usdc               The deployed USDC token.
    /// @return cuts         The facet cuts (ERC165 + AccessControl + CCTPBridgeAdapter).
    /// @return init         The {CCTPBridgeAdapterInit} initializer address.
    /// @return initCalldata The `init(admin, tokenMessenger, messageTransmitter, usdc)` calldata.
    function buildCuts(address admin, address tokenMessenger, address messageTransmitter, address usdc)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new CCTPBridgeAdapter()));
        init = address(new CCTPBridgeAdapterInit());
        initCalldata = abi.encodeCall(CCTPBridgeAdapterInit.init, (admin, tokenMessenger, messageTransmitter, usdc));
    }

    /// @notice Deploys a CCTP adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin              The adapter admin.
    /// @param tokenMessenger     The deployed CCTP v2 `TokenMessengerV2`.
    /// @param messageTransmitter The deployed CCTP v2 `MessageTransmitterV2`.
    /// @param usdc               The deployed USDC token.
    /// @return adapter The deployed CCTP adapter diamond address.
    function run(address admin, address tokenMessenger, address messageTransmitter, address usdc)
        external
        returns (address adapter)
    {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            buildCuts(admin, tokenMessenger, messageTransmitter, usdc);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
