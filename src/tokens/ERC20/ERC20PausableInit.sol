// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";

/// @title ERC20PausableInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ERC-20 Pausable extension recipe — seeds the shared Pausable state
///         (registering IPausable) and grants `admin_` the DEFAULT_ADMIN_ROLE that gates `pause()`/`unpause()`.
///         Delegatecalled by {Diamond.initialize} (through {MultiInit}) inside the initializing window opened by
///         the diamond, alongside the base {ERC20Init}; it must NOT open its own pre/postInitializer. Because the
///         base {ERC20} facet moves tokens via {ERC20Lib} directly, the {ERC20Pausable} facet replaces the public
///         `transfer`/`transferFrom` with pause-gated variants (see {DeployERC20Pausable}).
contract ERC20PausableInit {
    function init(address admin_) external {
        PausableLib.__Pausable_init();
        AccessControlLib.__AccessControl_init(admin_);
    }
}
