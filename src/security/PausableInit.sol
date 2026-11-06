// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";

/// @title PausableInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Seeds the explicit AccessControl admin and the Pausable module in one initialization window.
/// @dev Delegatecall through the diamond's initializer, directly or through MultiInit.
/// @custom:lattice-kind bundle
contract PausableInit {
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls pause/unpause).
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-initializes Pausable;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence AccessControl;Pausable;
    /// @custom:lattice-param admin authority;
    /// @custom:lattice-registers-interfaces
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        PausableLib.__Pausable_init();
    }
}

