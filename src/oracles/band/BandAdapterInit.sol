// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {BandAdapterLib} from "@lattice/oracles/band/BandAdapterLib.sol";

/// @title BandAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Band price-feed adapter diamond — seeds AccessControl (so the feed registry
///         setters are admin-gated), registers the IBandAdapter interface (ERC-165), and wires the Band
///         StdReference the adapter reads rates from. Delegatecalled by {Lattice.initialize} inside the
///         initializing window (so it must NOT open its own pre/postInitializer; each `__*_init` guard passes
///         because the window is already open). Unlike the registry-only adapters, Band's `__BandAdapter_init`
///         takes the external StdReference address and reverts `BandReferenceIsZero` if it is the zero address.
/// @custom:lattice-kind bundle
contract BandAdapterInit {
    /// @notice Runs the Band adapter + access-control module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the feed registry and `setReference`).
    /// @param reference_ The Band StdReference contract the adapter reads rates from.
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-initializes BandAdapter;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence AccessControl;BandAdapter;
    /// @custom:lattice-param admin authority;
    /// @custom:lattice-param reference_;
    /// @custom:lattice-registers-interfaces
    function init(address admin, address reference_) external {
        AccessControlLib.__AccessControl_init(admin);
        BandAdapterLib.__BandAdapter_init(reference_);
    }
}
