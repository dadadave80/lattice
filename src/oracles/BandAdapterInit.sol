// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {BandAdapterLib} from "@lattice/oracles/libraries/BandAdapterLib.sol";

/// @title BandAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Band price-feed adapter diamond — seeds AccessControl (so the feed registry
///         setters are admin-gated), registers the IBandAdapter interface (ERC-165), and wires the Band
///         StdReference the adapter reads rates from. Delegatecalled by {Diamond.initialize} inside the
///         initializing window (so it must NOT open its own pre/postInitializer; each `__*_init` guard passes
///         because the window is already open). Unlike the registry-only adapters, Band's `__BandAdapter_init`
///         takes the external StdReference address and reverts `BandReferenceIsZero` if it is the zero address.
contract BandAdapterInit {
    /// @notice Runs the Band adapter + access-control module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the feed registry and `setReference`).
    /// @param reference_ The Band StdReference contract the adapter reads rates from.
    function init(address admin, address reference_) external {
        AccessControlLib.__AccessControl_init(admin);
        BandAdapterLib.__BandAdapter_init(reference_);
    }
}
