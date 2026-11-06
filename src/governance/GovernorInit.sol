// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GovernorLib} from "@lattice/governance/libraries/GovernorLib.sol";

/// @title GovernorInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Seeds a Governor with explicit vote-token, timelock and voting configuration.
/// @dev Run through the diamond initialization window. Initialize AccessControl and the timelock first;
///      configure the Governor's proposer/executor authority in that same composition. This step grants no roles.
/// @custom:lattice-kind step
contract GovernorInit {
    /// @custom:lattice-initializes Governor;
    /// @custom:lattice-after Votes convention configured-token-state;
    /// @custom:lattice-after TimelockController convention configured-timelock-state;
    /// @custom:lattice-after AccessControl convention timelock-role-bootstrap;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-param name_;
    /// @custom:lattice-param token_;
    /// @custom:lattice-param timelock_;
    /// @custom:lattice-param votingDelay_ rule=token-clock-ticks;
    /// @custom:lattice-param votingPeriod_ rule=token-clock-ticks-positive;
    /// @custom:lattice-param proposalThreshold_;
    /// @custom:lattice-param quorumNumerator_ unit=percent rule=0-to-100;
    /// @custom:lattice-registers-interfaces
    function init(
        string memory name_,
        address token_,
        address timelock_,
        uint48 votingDelay_,
        uint32 votingPeriod_,
        uint256 proposalThreshold_,
        uint256 quorumNumerator_
    ) external {
        GovernorLib.__Governor_init(
            name_, token_, timelock_, votingDelay_, votingPeriod_, proposalThreshold_, quorumNumerator_
        );
    }
}
