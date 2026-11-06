// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ChainlinkCREAdapterLib} from "@lattice/oracles/chainlink/ChainlinkCREAdapterLib.sol";

/// @title ChainlinkCREAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Chainlink CRE adapter diamond — registers the canonical IReceiver interface
///         (ERC-165) so CRE tooling detects the receiver, and seeds AccessControl so `setForwarder`/`setWorkflow`
///         are admin-gated. Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT
///         open its own pre/postInitializer; each `__*_init` guard passes because the window is already open).
///         Companion to the {ERC2981Init} pattern — a first-class production deploy artifact.
///         The KeystoneForwarder + workflow allowlist are configured post-deploy via the admin-gated setters.
/// @custom:lattice-kind bundle
contract ChainlinkCREAdapterInit {
    /// @notice Runs the CRE adapter + access-control module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls `setForwarder`/`setWorkflow`).
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-initializes ChainlinkCREAdapter;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence AccessControl;ChainlinkCREAdapter;
    /// @custom:lattice-param admin authority;
    /// @custom:lattice-registers-interfaces
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        ChainlinkCREAdapterLib.__ChainlinkCREAdapter_init();
    }
}
