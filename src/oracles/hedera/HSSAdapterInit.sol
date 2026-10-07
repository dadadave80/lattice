// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {HSSAdapterLib, HSS_SCHEDULER_ROLE} from "@lattice/oracles/hedera/HSSAdapterLib.sol";

/// @title HSSAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Hedera Schedule Service diamond — seeds AccessControl, grants `admin`
///         the scheduler role (scheduling, deleting and authorizing schedules the diamond pays for) and
///         registers the IHSSAdapter interface (ERC-165). Delegatecalled by {Diamond.initialize} inside the
///         initializing window (so it must NOT open its own pre/postInitializer). Schedules are created later
///         via `scheduleCall`, so no schedule reference is needed at init time.
contract HSSAdapterInit {
    /// @notice Runs the HSS adapter + access-control module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` and `HSS_SCHEDULER_ROLE`.
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        AccessControlLib._grantRole(HSS_SCHEDULER_ROLE, admin);
        HSSAdapterLib.__HSSAdapter_init();
    }
}
