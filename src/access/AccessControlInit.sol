// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";

/// @title AccessControlInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an AccessControl role diamond — grants the `DEFAULT_ADMIN_ROLE` to `admin`
///         and registers the IAccessControl interface (ERC-165). Delegatecalled by {Diamond.initialize} inside
///         the initializing window (so it must NOT open its own pre/postInitializer; the `__AccessControl_init`
///         guard passes because the window is already open). Companion to the {ERC20Init}/{ERC2981Init} patterns
///         — a first-class production deploy artifact.
contract AccessControlInit {
    /// @notice Seeds the AccessControl module. MUST be invoked via the diamond's `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
    }
}
