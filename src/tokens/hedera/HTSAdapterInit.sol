// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {HTS_MANAGER_ROLE, HTS_OPERATOR_ROLE, HTSAdapterLib} from "@lattice/tokens/hedera/HTSAdapterLib.sol";

/// @title HTSAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an HTS-account diamond — seeds AccessControl, grants `admin` both HTS roles
///         (associations / token creation and treasury operations) and registers the IHTSAdapter interface
///         (ERC-165). Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT open
///         its own pre/postInitializer). Token associations happen later via `associateToken`, so no external
///         reference is needed at init time.
contract HTSAdapterInit {
    /// @notice Runs the HTS adapter + access-control module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`, `HTS_MANAGER_ROLE` and `HTS_OPERATOR_ROLE`.
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        AccessControlLib._grantRole(HTS_MANAGER_ROLE, admin);
        AccessControlLib._grantRole(HTS_OPERATOR_ROLE, admin);
        HTSAdapterLib.__HTSAdapter_init();
    }
}
