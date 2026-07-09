// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlEnumerableLib} from "@lattice/access/libraries/AccessControlEnumerableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";

/// @title AccessControlEnumerableInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an AccessControlEnumerable diamond — seeds the base role storage
///         (`DEFAULT_ADMIN_ROLE` to `admin`, IAccessControl ERC-165) AND registers the IAccessControlEnumerable
///         interface, both inside the ONE initializing window {Diamond.initialize} opens (no pre/postInitializer).
contract AccessControlEnumerableInit {
    /// @notice Seeds the AccessControl + enumeration modules.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        AccessControlEnumerableLib.__AccessControlEnumerable_init();
    }
}
