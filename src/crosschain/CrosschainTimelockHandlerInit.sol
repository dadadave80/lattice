// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {CrosschainLinkLib} from "@lattice/crosschain/libraries/CrosschainLinkLib.sol";
import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";

/// @title CrosschainTimelockHandlerInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a cross-chain governance diamond — seeds AccessControl, a
///         {TimelockController} whose sole proposer is the Diamond itself (so only the authenticated cross-chain
///         handler can schedule operations) with open execution, and the {CrosschainLink} messaging registry.
///         Delegatecalled by {Diamond.initialize} inside the initializing window, so `address(this)` is the
///         Diamond and it must NOT open its own pre/postInitializer (each `__*_init` guard passes because the
///         window is already open).
contract CrosschainTimelockHandlerInit {
    /// @notice Runs the access-control + timelock + crosschain-link module initializers. MUST be invoked via the
    ///         diamond's `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (timelock admin + link/handler registry admin).
    /// @param minDelay The timelock's minimum operation delay.
    function init(address admin, uint256 minDelay) external {
        AccessControlLib.__AccessControl_init(admin);

        address[] memory proposers = new address[](1);
        proposers[0] = address(this); // the Diamond proposes, via the authenticated cross-chain handler
        address[] memory executors = new address[](1);
        executors[0] = address(0); // open execution
        TimelockControllerLib.__TimelockController_init(minDelay, proposers, executors, admin);

        CrosschainLinkLib.__CrosschainLink_init();
    }
}
