// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {CircuitBreakerLib} from "@lattice/security/libraries/CircuitBreakerLib.sol";

/// @title CircuitBreakerInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Seeds the explicit AccessControl admin and the CircuitBreaker module in one initialization window.
/// @dev Delegatecall through the diamond's initializer, directly or through MultiInit.
/// @custom:lattice-kind bundle
contract CircuitBreakerInit {
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the breaker configuration).
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-initializes CircuitBreaker;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence AccessControl;CircuitBreaker;
    /// @custom:lattice-param admin authority;
    /// @custom:lattice-registers-interfaces
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        CircuitBreakerLib.__CircuitBreaker_init();
    }
}

