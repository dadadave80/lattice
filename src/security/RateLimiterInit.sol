// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {RateLimiterLib} from "@lattice/security/libraries/RateLimiterLib.sol";

/// @title RateLimiterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Seeds the explicit AccessControl admin and the RateLimiter module in one initialization window.
/// @dev Delegatecall through the diamond's initializer, directly or through MultiInit.
contract RateLimiterInit {
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls `configure`).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        RateLimiterLib.__RateLimiter_init();
    }
}

