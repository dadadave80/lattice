// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ICrosschainTimelockHandler
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Events/errors for the cross-chain governance handler: an {IERC7786MessageHandler} that schedules
///         an operation on the co-mounted {TimelockController} from an authenticated inbound message
///         (e.g. an L1 governor proposing a timelocked action on an L2 Diamond).
interface ICrosschainTimelockHandler {
    /// @notice Emitted when an inbound cross-chain message schedules a timelock operation.
    event CrosschainOperationScheduled(
        bytes32 indexed receiveId, bytes32 indexed operationId, address target, uint256 value, uint256 delay
    );

    /// @notice `processMessage` was called by something other than the Diamond's own authenticated
    ///         `receiveMessage` dispatch (`msg.sender != address(this)`).
    error CrosschainTimelockUnauthorizedCaller(address caller);
}
