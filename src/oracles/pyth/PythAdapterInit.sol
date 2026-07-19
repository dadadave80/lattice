// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {PythAdapterLib} from "@lattice/oracles/libraries/PythAdapterLib.sol";

/// @title PythAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Pyth price-feed adapter diamond — seeds AccessControl (so the feed registry
///         setters are admin-gated), registers the IPythAdapter interface (ERC-165), and wires the Pyth contract
///         reference the adapter pulls prices from. Delegatecalled by {Diamond.initialize} inside the initializing
///         window (so it must NOT open its own pre/postInitializer; each `__*_init` guard passes because the
///         window is already open). Unlike the registry-only adapters, Pyth's `__PythAdapter_init` takes the
///         external Pyth address because reads and the update path both dispatch through it.
contract PythAdapterInit {
    /// @notice Runs the Pyth adapter + access-control module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the feed registry and `setPyth`).
    /// @param pyth The Pyth contract the adapter reads prices from and forwards update fees to.
    function init(address admin, address pyth) external {
        AccessControlLib.__AccessControl_init(admin);
        PythAdapterLib.__PythAdapter_init(pyth);
    }
}
