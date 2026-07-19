// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {TellorAdapterLib} from "@lattice/oracles/tellor/TellorAdapterLib.sol";

/// @title TellorAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Tellor price-feed adapter diamond — seeds AccessControl (so the feed
///         registry setters are admin-gated), registers the ITellorAdapter interface (ERC-165), and wires the
///         Tellor oracle the adapter reads reports from. Delegatecalled by {Diamond.initialize} inside the
///         initializing window (so it must NOT open its own pre/postInitializer; each `__*_init` guard passes
///         because the window is already open). Unlike the registry-only adapters, Tellor's `__TellorAdapter_init`
///         takes the external Tellor address and reverts `TellorContractIsZero` if it is the zero address.
contract TellorAdapterInit {
    /// @notice Runs the Tellor adapter + access-control module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the feed registry and `setTellor`).
    /// @param tellor The Tellor oracle contract the adapter reads reports from.
    function init(address admin, address tellor) external {
        AccessControlLib.__AccessControl_init(admin);
        TellorAdapterLib.__TellorAdapter_init(tellor);
    }
}
