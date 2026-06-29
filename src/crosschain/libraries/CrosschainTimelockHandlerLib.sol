// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";
import {ICrosschainTimelockHandler} from "@lattice/interfaces/crosschain/ICrosschainTimelockHandler.sol";

/// @dev Handler tag this module registers/dispatches under: `bytes4(keccak256("lattice.crosschain.TimelockSchedule"))`.
bytes4 constant CROSSCHAIN_TIMELOCK_TAG = 0x4c71a524;

/// @title CrosschainTimelockHandlerLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice STATELESS handler: schedules an operation on the co-mounted {TimelockController} from an
///         authenticated inbound ERC-7786 message. Holds no ERC-7201 storage of its own.
/// @dev Trust model: {CrosschainLink} has already authenticated the gateway + source counterpart before
///      dispatching here, so the linked counterpart is effectively a timelock proposer. `schedule` checks
///      PROPOSER_ROLE against `msg.sender`, which is the Diamond itself under the self-dispatch — so the
///      Diamond must hold PROPOSER_ROLE (granted at timelock init or by an admin). The timelock delay +
///      CANCELLER_ROLE provide the safety window over inbound proposals.
library CrosschainTimelockHandlerLib {
    /// @notice Schedules the encoded operation on the co-mounted {TimelockController}. Callable only via
    ///         the Diamond's own authenticated `receiveMessage` dispatch (`msg.sender == address(this)`).
    /// @param receiveId The de-duplicated inbound message id (replay already checked by {CrosschainLink}).
    /// @param payload   `abi.encode(address target, uint256 value, bytes data, bytes32 predecessor,
    ///                  bytes32 salt, uint256 delay)`. The timelock enforces `delay >= minDelay`.
    function processMessage(bytes32 receiveId, bytes calldata payload) internal {
        if (msg.sender != address(this)) {
            revert ICrosschainTimelockHandler.CrosschainTimelockUnauthorizedCaller(msg.sender);
        }

        (address target, uint256 value, bytes memory data, bytes32 predecessor, bytes32 salt, uint256 delay) =
            abi.decode(payload, (address, uint256, bytes, bytes32, bytes32, uint256));

        // schedule() checks PROPOSER_ROLE against msg.sender (the Diamond, under self-dispatch) and the
        // timelock enforces the minimum delay. The cross-chain link + counterpart auth is the real gate.
        TimelockControllerLib.schedule(target, value, data, predecessor, salt, delay);

        emit ICrosschainTimelockHandler.CrosschainOperationScheduled(
            receiveId, TimelockControllerLib.hashOperation(target, value, data, predecessor, salt), target, value, delay
        );
    }
}
