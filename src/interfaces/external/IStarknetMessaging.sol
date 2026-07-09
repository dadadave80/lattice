// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IStarknetMessaging
/// @author Vendored minimal subset of Starknet's `IStarknetMessaging` (https://github.com/starkware-libs/cairo-lang).
///         Upstream is Apache-2.0.
/// @notice The L1-side Starknet core messaging surface an L1 <-> L2 connector needs: fee-escrowed L1 -> L2
///         sends, pull-based L2 -> L1 consumes, and the two-step sender-only L1 -> L2 cancellation flow.
/// @dev Semantics (per the upstream `StarknetMessaging` implementation):
///      - `sendMessageToL2` requires `0 < msg.value <= getMaxL1MsgFee()`; the fee is ESCROWED by the core and
///        NEVER refunded — not even when the message is later cancelled.
///      - `consumeMessageFromL2` authenticates by `msg.sender` (it only consumes messages addressed to the
///        caller); `l2ToL1Messages(msgHash)` is a COUNTER (the same message can exist N times), decremented
///        once per consume, and the call reverts when it is zero.
///      - Cancellation is two-step: `startL1ToL2MessageCancellation`, then `messageCancellationDelay()` seconds
///        later `cancelL1ToL2Message` with the SAME arguments. Both derive the message hash from `msg.sender`,
///        so ONLY the original L1 sender can cancel its own messages.
///      - Every L2-bound value (`toAddress`, `selector`, each payload element) must be a felt252, i.e. strictly
///        below the Stark field prime `2**251 + 17 * 2**192 + 1`.
interface IStarknetMessaging {
    /// @notice Returns the max fee (in wei) the core accepts per single L1 -> L2 message (1 ether upstream).
    function getMaxL1MsgFee() external pure returns (uint256);

    /// @notice Returns the number of consumable L2 -> L1 messages with hash `msgHash` (a counter, not a flag).
    function l2ToL1Messages(bytes32 msgHash) external view returns (uint256);

    /// @notice Returns the hash of an L1 -> L2 message
    ///         (`keccak256(abi.encodePacked(fromAddress, toAddress, nonce, selector, payload.length, payload))`).
    function l1ToL2MsgHash(
        address fromAddress,
        uint256 toAddress,
        uint256 selector,
        uint256[] calldata payload,
        uint256 nonce
    ) external pure returns (bytes32);

    /// @notice Sends a message to the L2 contract `toAddress`, invoking its `selector` l1_handler with
    ///         `payload`. `msg.value` is the message fee: escrowed, never refunded.
    /// @return msgHash The message hash.
    /// @return nonce   The core-minted message nonce (needed later for cancellation).
    function sendMessageToL2(uint256 toAddress, uint256 selector, uint256[] calldata payload)
        external
        payable
        returns (bytes32 msgHash, uint256 nonce);

    /// @notice Consumes a message sent from the L2 contract `fromAddress` and addressed to `msg.sender`.
    ///         Decrements the message counter; reverts when it is zero.
    /// @return msgHash The consumed message hash.
    function consumeMessageFromL2(uint256 fromAddress, uint256[] calldata payload) external returns (bytes32 msgHash);

    /// @notice Starts the cancellation of a pending L1 -> L2 message previously sent by `msg.sender`. The
    ///         message can be cancelled `messageCancellationDelay()` seconds after this call.
    function startL1ToL2MessageCancellation(
        uint256 toAddress,
        uint256 selector,
        uint256[] calldata payload,
        uint256 nonce
    ) external returns (bytes32 msgHash);

    /// @notice Cancels an L1 -> L2 message previously sent by `msg.sender`, at least
    ///         `messageCancellationDelay()` seconds after {startL1ToL2MessageCancellation}. The escrowed
    ///         message fee is NOT refunded.
    function cancelL1ToL2Message(uint256 toAddress, uint256 selector, uint256[] calldata payload, uint256 nonce)
        external
        returns (bytes32 msgHash);
}
