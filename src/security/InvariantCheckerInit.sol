// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {InvariantCheckerLib} from "@lattice/security/libraries/InvariantCheckerLib.sol";

/// @title InvariantCheckerInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Seeds the explicit AccessControl admin and the InvariantChecker module in one initialization window.
/// @dev Delegatecall through the diamond's initializer, directly or through MultiInit.
/// @custom:lattice-kind bundle
contract InvariantCheckerInit {
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls invariant registration).
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-initializes InvariantChecker;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence AccessControl;InvariantChecker;
    /// @custom:lattice-param admin authority;
    /// @custom:lattice-registers-interfaces
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        InvariantCheckerLib.__InvariantChecker_init();
    }
}

