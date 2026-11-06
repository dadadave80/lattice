// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {CircuitBreakerLib} from "@lattice/security/libraries/CircuitBreakerLib.sol";

/// @title CircuitBreakerInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Seeds the explicit AccessControl admin and the CircuitBreaker module in one initialization window.
/// @dev Delegatecall through the diamond's initializer, directly or through MultiInit.
contract CircuitBreakerInit {
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the breaker configuration).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        CircuitBreakerLib.__CircuitBreaker_init();
    }
}

