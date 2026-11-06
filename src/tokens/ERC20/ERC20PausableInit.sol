// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";

/// @title ERC20PausableInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ERC-20 Pausable extension recipe — registers the IPausable
///         interface (ERC-165 — the only init the pausable module needs; `_paused` is the zero default) and grants `admin_` the DEFAULT_ADMIN_ROLE that gates `pause()`/`unpause()`.
///         Delegatecalled by {Lattice.initialize} (through {MultiInit}) inside the initializing window opened by
///         the diamond, alongside the base {ERC20Init}; it must NOT open its own pre/postInitializer. Because the
///         base {ERC20} facet moves tokens via {ERC20Lib} directly, the {ERC20Pausable} facet replaces the public
///         `transfer`/`transferFrom` with pause-gated variants (see {DeployERC20Pausable}).
/// @custom:lattice-kind bundle
contract ERC20PausableInit {
    /// @custom:lattice-initializes Pausable;
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence Pausable;AccessControl;
    /// @custom:lattice-param admin_ authority;
    /// @custom:lattice-registers-interfaces
    function init(address admin_) external {
        PausableLib.__Pausable_init();
        AccessControlLib.__AccessControl_init(admin_);
    }
}
