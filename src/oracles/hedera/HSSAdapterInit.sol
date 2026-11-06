// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {HSSAdapterLib, HSS_SCHEDULER_ROLE} from "@lattice/oracles/hedera/HSSAdapterLib.sol";

/// @title HSSAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Hedera Schedule Service diamond — seeds AccessControl, grants `admin`
///         the scheduler role (scheduling, deleting and authorizing schedules the diamond pays for) and
///         registers IHSSAdapter and IHSSAdapterRecovery (ERC-165). Both matching facets must be cut before init. Delegatecalled by {Diamond.initialize} inside the
///         initializing window (so it must NOT open its own pre/postInitializer). Schedules are created later
///         via `scheduleCall`, so no schedule reference is needed at init time.
/// @custom:lattice-kind bundle
contract HSSAdapterInit {
    /// @notice Runs the HSS adapter + access-control module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` and `HSS_SCHEDULER_ROLE`.
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-initializes HSSAdapter;
    /// @custom:lattice-after HSSAdapterRecovery hard recovery-routes-installed-before-init;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence AccessControl;HSSAdapter;
    /// @custom:lattice-param admin authority;
    /// @custom:lattice-registers-interfaces
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        AccessControlLib._grantRole(HSS_SCHEDULER_ROLE, admin);
        HSSAdapterLib.__HSSAdapter_init();
    }
}
