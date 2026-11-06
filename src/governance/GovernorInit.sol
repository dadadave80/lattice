// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GovernorLib} from "@lattice/governance/libraries/GovernorLib.sol";

/// @title GovernorInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Seeds a Governor with explicit vote-token, timelock and voting configuration.
/// @dev Run through the diamond initialization window. Initialize AccessControl and the timelock first;
///      configure the Governor's proposer/executor authority in that same composition. This step grants no roles.
contract GovernorInit {
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
