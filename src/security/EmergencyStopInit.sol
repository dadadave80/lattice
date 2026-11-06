// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";

/// @title EmergencyStopInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Seeds the explicit AccessControl admin and the EmergencyStop module in one initialization window.
/// @dev Delegatecall through the diamond's initializer, directly or through MultiInit.
contract EmergencyStopInit {
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (manages guardians and resumes operation).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        EmergencyStopLib.__EmergencyStop_init();
    }
}

