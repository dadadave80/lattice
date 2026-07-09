// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AggregatorExecAdapterLib} from "@lattice/defi/libraries/AggregatorExecAdapterLib.sol";
import {IAggregatorExecAdapter} from "@lattice/interfaces/defi/IAggregatorExecAdapter.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

/// @title AggregatorExecAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a generic swap/bridge execution diamond — seeds AccessControl (so the
///         `(aggregator, selector)` allow-list setter is `DEFAULT_ADMIN_ROLE`-gated), the reentrancy guard (the
///         exec path is `nonReentrant`), and registers the IAggregatorExecAdapter interface via ERC-165.
///         Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT open its own
///         pre/postInitializer; each `__*_init` guard passes because the window is already open). Reverts
///         {AggregatorExecZeroAdmin} if `admin` is the zero address.
contract AggregatorExecAdapterInit {
    /// @notice Runs the access-control + reentrancy-guard + adapter initializers. MUST be invoked via the
    ///         diamond's `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the allow-list setter).
    function init(address admin) external {
        if (admin == address(0)) revert IAggregatorExecAdapter.AggregatorExecZeroAdmin();
        AccessControlLib.__AccessControl_init(admin);
        ReentrancyGuardLib.__ReentrancyGuard_init();
        AggregatorExecAdapterLib.__AggregatorExecAdapter_init();
    }
}
