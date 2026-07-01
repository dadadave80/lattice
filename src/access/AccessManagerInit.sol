// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessManagerLib} from "@lattice/access/libraries/AccessManagerLib.sol";

/// @title AccessManagerInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an AccessManager authority diamond — grants the initial `ADMIN_ROLE` to
///         `admin` and registers the IAccessManager interface (ERC-165). Delegatecalled by {Diamond.initialize}
///         inside the initializing window (so it must NOT open its own pre/postInitializer; the
///         `__AccessManager_init` guard passes because the window is already open). Reverts with
///         {AccessManagerInvalidInitialAdmin} if `admin` is the zero address.
contract AccessManagerInit {
    /// @notice Seeds the AccessManager module. MUST be invoked via the diamond's `initialize` `_init` delegatecall.
    /// @param admin The address granted the initial `ADMIN_ROLE`.
    function init(address admin) external {
        AccessManagerLib.__AccessManager_init(admin);
    }
}
