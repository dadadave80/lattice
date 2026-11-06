// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";

/// @title PausableInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Seeds the explicit AccessControl admin and the Pausable module in one initialization window.
/// @dev Delegatecall through the diamond's initializer, directly or through MultiInit.
contract PausableInit {
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls pause/unpause).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        PausableLib.__Pausable_init();
    }
}

