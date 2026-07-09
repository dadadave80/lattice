// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ShieldedPoolLib} from "@lattice/privacy/libraries/ShieldedPoolLib.sol";

/// @title ShieldedPoolInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a ShieldedPool diamond — seeds AccessControl (so `createPool` is
///         `DEFAULT_ADMIN_ROLE`-gated) and registers the IShieldedPool interface (ERC-165). Delegatecalled by
///         {Diamond.initialize} inside the initializing window (so it must NOT open its own pre/postInitializer;
///         each `__*_init` guard passes because the window is already open).
contract ShieldedPoolInit {
    /// @notice Runs the access-control + ShieldedPool module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls `createPool`).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        ShieldedPoolLib.__ShieldedPool_init();
    }
}
