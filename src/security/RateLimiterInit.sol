// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {RateLimiterLib} from "@lattice/security/libraries/RateLimiterLib.sol";

/// @title RateLimiterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Seeds the explicit AccessControl admin and the RateLimiter module in one initialization window.
/// @dev Delegatecall through the diamond's initializer, directly or through MultiInit.
/// @custom:lattice-kind bundle
contract RateLimiterInit {
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls `configure`).
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-initializes RateLimiter;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence AccessControl;RateLimiter;
    /// @custom:lattice-param admin authority;
    /// @custom:lattice-registers-interfaces
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        RateLimiterLib.__RateLimiter_init();
    }
}

