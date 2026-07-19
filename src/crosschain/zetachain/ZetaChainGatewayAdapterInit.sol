// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ZetaChainGatewayAdapterLib} from "@lattice/crosschain/zetachain/ZetaChainGatewayAdapterLib.sol";

/// @title ZetaChainGatewayAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a ZetaChain `GatewayEVM` gateway-adapter diamond — seeds AccessControl so the
///         gateway/remote/revert-gas setters are admin-gated, wires the DEPLOYED `GatewayEVM` (address varies per
///         connected chain), registers the hub route (ZEVM universal app) in BOTH the forward and reverse maps,
///         seeds the default `onRevertGasLimit`, and registers the ERC-7786 gateway-source interface via ERC-165.
///         Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT open its own
///         pre/postInitializer; each `__*_init` guard passes because the window is already open). Companion to the
///         {LayerZeroGatewayAdapterInit} pattern — a first-class production deploy artifact.
contract ZetaChainGatewayAdapterInit {
    /// @notice Runs the access-control + ZetaChain-adapter module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param gateway The ZetaChain `GatewayEVM` the adapter dispatches `call` to and accepts `onCall` from.
    /// @param hubChainId The hub chainId whose ZEVM universal app terminates the route.
    /// @param hubRemoteApp The trusted ZEVM universal app (hub) for `hubChainId`.
    /// @param defaultOnRevertGasLimit The default `onRevertGasLimit` used to build per-message `RevertOptions`.
    function init(
        address admin,
        address gateway,
        uint256 hubChainId,
        address hubRemoteApp,
        uint256 defaultOnRevertGasLimit
    ) external {
        AccessControlLib.__AccessControl_init(admin);
        ZetaChainGatewayAdapterLib.__ZetaChainGatewayAdapter_init(
            gateway, hubChainId, hubRemoteApp, defaultOnRevertGasLimit
        );
    }
}
