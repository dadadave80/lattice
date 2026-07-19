// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {HyperlaneGatewayAdapterLib} from "@lattice/crosschain/hyperlane/HyperlaneGatewayAdapterLib.sol";

/// @title HyperlaneGatewayAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Hyperlane gateway-adapter diamond — seeds AccessControl so the domain,
///         remote and destination setters are admin-gated, and wires the Hyperlane Mailbox (zero reverts),
///         registering BOTH the ERC-7786 gateway-source interface (shared) and the adapter's own
///         IHyperlaneGatewayAdapter interface via ERC-165. v1 uses the Mailbox DEFAULT ISM — no custom ISM is
///         pinned here. Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT
///         open its own pre/postInitializer; each `__*_init` guard passes because the window is already open).
///         Companion to the {LayerZeroGatewayAdapterInit} pattern — a first-class production deploy artifact.
contract HyperlaneGatewayAdapterInit {
    /// @notice Runs the access-control + Hyperlane-adapter module initializers. MUST be invoked via the
    ///         diamond's `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param mailbox The Hyperlane Mailbox the adapter dispatches to and accepts `handle` deliveries from.
    function init(address admin, address mailbox) external {
        AccessControlLib.__AccessControl_init(admin);
        HyperlaneGatewayAdapterLib.__HyperlaneGatewayAdapter_init(mailbox);
    }
}
