// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GovernorLib} from "@lattice/governance/libraries/GovernorLib.sol";
import {IGovernor} from "@lattice/interfaces/governance/IGovernor.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @title GovernorInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Seeds a Governor with explicit vote-token, timelock and voting configuration.
/// @dev Run through the diamond initialization window. Initialize AccessControl and the timelock first;
///      configure the Governor's proposer/executor authority in that same composition. This step grants no roles.
///      A declared GovernedDiamondCut route requires a zero/self timelock by default. Its trusted initializer
///      checks the same policy when run later, so reversing module order cannot hide incompatible wiring.
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

    /// @notice Explicitly acknowledge a deliberate external-timelock governed-cut authority design.
    /// @dev This exemption grants no roles and does not make an external timelock able to execute cuts.
    ///      The trusted governed-cut initializer must declare its installed route in the same composition.
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
    /// @custom:lattice-param acknowledgeIncompatibleCutExecutor_ rule=required-true-explicit-external-executor-acknowledgement;
    /// @custom:lattice-registers-interfaces
    function initWithExternalTimelockOptOut(
        string memory name_,
        address token_,
        address timelock_,
        uint48 votingDelay_,
        uint32 votingPeriod_,
        uint256 proposalThreshold_,
        uint256 quorumNumerator_,
        bool acknowledgeIncompatibleCutExecutor_
    ) external {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        if (!acknowledgeIncompatibleCutExecutor_) revert IGovernor.GovernorTimelockOptOutNotAcknowledged();
        GovernorLib.__Governor_init(
            name_, token_, timelock_, votingDelay_, votingPeriod_, proposalThreshold_, quorumNumerator_, true
        );
    }

    /// @notice Backfill or refresh the governed-cut policy in an authorized initialization batch.
    /// @dev Declares only the installed cut owner; preserves Governor configuration, roles and emergency state.
    ///      The caller's trusted batch must pair this with the actual governed-cut flavor. Legacy unmarked
    ///      deployments are not protected until this declaration succeeds. Incompatible current timelocks revert.
    /// @custom:lattice-initializes Governor with policy=governed-cut-route;
    /// @custom:lattice-after GovernedDiamondCut convention existing-governed-role-policy;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-param none;
    function registerGovernedCutTopology() external {
        GovernorLib.__registerGovernedCutTopology();
    }
}
