// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AccessControlTimedLib} from "@lattice/access/libraries/AccessControlTimedLib.sol";

/// @title AccessControlTimedInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an AccessControlTimed diamond — seeds the base role storage
///         (`DEFAULT_ADMIN_ROLE` to `admin`, IAccessControl ERC-165) AND registers the IAccessControlTimed
///         interface, both inside the ONE initializing window {Diamond.initialize} opens (no pre/postInitializer).
contract AccessControlTimedInit {
    /// @notice Seeds the AccessControl + timed-role modules.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        AccessControlTimedLib.__AccessControlTimed_init();
    }
}
