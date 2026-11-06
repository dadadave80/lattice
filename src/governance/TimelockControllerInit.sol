// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";

/// @title TimelockControllerInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Seeds a timelock's minimum delay and explicit proposer/executor roles.
/// @dev Run after AccessControl in the same diamond initialization window. The library grants the diamond
///      its own admin role; the caller must already have seeded any external admin through AccessControlInit.
contract TimelockControllerInit {
    /// @param admin The admin already seeded by the preceding AccessControl step; no extra role is granted here.
    function init(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin) external {
        TimelockControllerLib.__TimelockController_init(minDelay, proposers, executors, admin);
    }
}
