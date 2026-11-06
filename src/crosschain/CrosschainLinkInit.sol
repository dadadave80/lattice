// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {CrosschainLinkLib} from "@lattice/crosschain/libraries/CrosschainLinkLib.sol";

/// @title CrosschainLinkInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an ERC-7786 messaging diamond — seeds AccessControl (so the link/handler
///         setters are admin-gated) and registers the ICrosschainLink interface (ERC-165). Delegatecalled by
///         {Lattice.initialize} inside the initializing window (so it must NOT open its own pre/postInitializer;
///         each `__*_init` guard passes because the window is already open). Companion to the
///         {AccessControlInit}/{ERC2981Init} patterns — a first-class production deploy artifact.
/// @custom:lattice-kind bundle
contract CrosschainLinkInit {
    /// @notice Runs the access-control + crosschain-link module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the link/handler registry).
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-initializes CrosschainLink;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence AccessControl;CrosschainLink;
    /// @custom:lattice-param admin authority;
    /// @custom:lattice-registers-interfaces
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        CrosschainLinkLib.__CrosschainLink_init();
    }
}
