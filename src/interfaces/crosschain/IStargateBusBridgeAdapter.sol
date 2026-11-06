// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IStargateBridgeAdapter} from "@lattice/interfaces/crosschain/IStargateBridgeAdapter.sol";

/// @title IStargateBusBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Stargate (https://github.com/stargate-protocol/stargate-v2)
/// @notice Optional ERC20 bus-enqueue capability alongside the frozen taxi adapter interface.
/// @dev Uses the existing registered pools/eids and unchanged SendTokenParams tuple. A successful call
///      queues an asynchronous transfer, not a delivered message: the upstream enqueue GUID/nonce are zero.
///      Ticket zero is valid. Retain passengerBytes; a driver needs an authenticated contiguous queue prefix.
///      No cancellation, expiry, delivery deadline, native pool, native drop or compose hook is provided.
interface IStargateBusBridgeAdapter {
    /// @notice A source-chain queue admission, not destination delivery or a LayerZero GUID.
    event StargateBusQueued(
        address indexed sender,
        address indexed token,
        uint256 indexed destinationChainId,
        uint72 ticketId,
        bytes passengerBytes,
        uint256 amountSentLD,
        uint256 amountReceivedLD,
        bytes32 recipient
    );

    /// @notice Bus calls require the exact current quoted fare, before any token movement.
    /// @dev The pinned pool ignores a failed surplus refund; rejecting surplus avoids that routine path.
    error StargateBusFeeMismatch(uint256 required, uint256 provided);

    /// @notice The configured pool returned a taxi-like or empty enqueue receipt; protocol review is required.
    error StargateBusUnexpectedReceipt(bytes32 guid, uint64 nonce, uint256 passengerLength);

    /// @notice The actual enqueue fare disagrees with the exact quote, or charges unsupported LZ tokens.
    error StargateBusUnexpectedFare(uint256 quoted, uint256 charged, uint256 lzTokenFee);

    /// @notice Quotes the native bus fare using the same validated parameters and mode as sendTokenBus.
    /// @dev Quotes do not reserve queue space, a fare or destination liquidity. A later send may revert.
    function quoteBusFee(IStargateBridgeAdapter.SendTokenParams calldata p) external view returns (uint256 nativeFee);

    /// @notice Pulls the caller's ERC20, queues a bus ride, resets approval and returns only its token dust.
    /// @dev msg.value must equal quoteBusFee(p); it is the fare only. The registered pool remains trusted.
    ///      The upstream driver/planner and LayerZero govern later dispatch/delivery, without a time bound.
    /// @return ticketId Valid queue ticket, including zero; scoped to upstream TokenMessaging/destination eid.
    /// @return passengerBytes Opaque upstream passenger data; keep it for monitoring or a direct upstream drive.
    /// @return amountSentLD Actual local token debit after shared-decimal dust removal.
    /// @return amountReceivedLD Locally settled destination amount after pool fees; not proof of delivery.
    function sendTokenBus(IStargateBridgeAdapter.SendTokenParams calldata p)
        external
        payable
        returns (uint72 ticketId, bytes memory passengerBytes, uint256 amountSentLD, uint256 amountReceivedLD);
}
