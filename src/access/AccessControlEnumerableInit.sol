// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlEnumerableLib} from "@lattice/access/libraries/AccessControlEnumerableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";

/// @title AccessControlEnumerableInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an AccessControlEnumerable diamond — seeds the base role storage
///         (`DEFAULT_ADMIN_ROLE` to `admin`, IAccessControl ERC-165) AND registers the IAccessControlEnumerable
///         interface, both inside the ONE initializing window {Lattice.initialize} opens (no pre/postInitializer).
/// @custom:lattice-kind bundle
contract AccessControlEnumerableInit {
    /// @notice Seeds the AccessControl + enumeration modules.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-initializes AccessControlEnumerable;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence AccessControl;AccessControlEnumerable;
    /// @custom:lattice-param admin authority;
    /// @custom:lattice-registers-interfaces
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        AccessControlEnumerableLib.__AccessControlEnumerable_init();
    }
}
