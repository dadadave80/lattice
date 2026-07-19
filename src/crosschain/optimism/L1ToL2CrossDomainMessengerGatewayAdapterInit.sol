// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {
    L1ToL2CrossDomainMessengerGatewayAdapterLib
} from "@lattice/crosschain/optimism/L1ToL2CrossDomainMessengerGatewayAdapterLib.sol";

/// @title L1ToL2CrossDomainMessengerGatewayAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a canonical OP Stack L1<->L2 `CrossDomainMessenger` gateway-adapter diamond —
///         seeds AccessControl so the counterpart/min-gas setters are admin-gated, seeds the fixed counterpart
///         `(counterpartChainId, counterpartAdapter)` + relay `minGasLimit`, and registers the ERC-7786
///         gateway-source interface via ERC-165. Unlike the {LayerZeroGatewayAdapterInit} / {CCIPGatewayAdapterInit}
///         siblings there is NO endpoint/router ctor arg: the messenger is the fixed predeploy constant
///         (`0x4200000000000000000000000000000000000007`). Delegatecalled by {Diamond.initialize} inside the
///         initializing window (so it must NOT open its own pre/postInitializer; each `__*_init` guard passes
///         because the window is already open). A first-class production deploy artifact.
contract L1ToL2CrossDomainMessengerGatewayAdapterInit {
    /// @notice Runs the access-control + adapter module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin              The address granted `DEFAULT_ADMIN_ROLE` (controls the counterpart/min-gas setters).
    /// @param counterpartChainId The paired-domain chain id.
    /// @param counterpartAdapter The sibling adapter on the paired domain (must be non-zero).
    /// @param minGasLimit        The `minGasLimit` the messenger relays outbound messages with.
    function init(address admin, uint256 counterpartChainId, address counterpartAdapter, uint32 minGasLimit) external {
        AccessControlLib.__AccessControl_init(admin);
        L1ToL2CrossDomainMessengerGatewayAdapterLib.__L1ToL2CrossDomainMessengerGatewayAdapter_init(
            counterpartChainId, counterpartAdapter, minGasLimit
        );
    }
}
