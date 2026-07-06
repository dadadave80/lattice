// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IStarknetMessaging} from "@lattice/interfaces/external/IStarknetMessaging.sol";

/// @title MockStarknetMessaging
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Starknet (https://github.com/starkware-libs/cairo-lang)
/// @notice Test double for the Starknet core (`StarknetMessaging`) that mirrors the upstream semantics the
///         adapter depends on: `sendMessageToL2` records its args verbatim, mints incrementing nonces, and
///         enforces `0 < fee <= 1 ether` plus the felt bounds (same revert strings as upstream);
///         `consumeMessageFromL2` tracks a consumable-message COUNTER keyed by the upstream
///         `l2ToL1MsgHash(fromAddress, consumer, payload)` (so the same message can exist N times and each
///         consume decrements once); the two-step cancellation derives the hash from `msg.sender` (sender-only,
///         like upstream) and enforces the cancellation delay. `mockSendMessageFromL2` is the test hook that
///         loads consumable L2 -> L1 messages.
contract MockStarknetMessaging is IStarknetMessaging {
    uint256 public constant MAX_L1_MSG_FEE = 1 ether;
    uint256 public constant CANCELLATION_DELAY = 5 days;
    uint256 internal constant FIELD_PRIME = 0x0800000000000011000000000000000000000000000000000000000000000001;

    /// @dev msgHash => fee + 1 (0 = no pending message), like upstream `l1ToL2Messages`.
    mapping(bytes32 msgHash => uint256 feePlusOne) public l1ToL2Messages;
    /// @dev msgHash => consumable-message COUNTER, like upstream `l2ToL1Messages`.
    mapping(bytes32 msgHash => uint256 count) internal _l2ToL1Messages;
    /// @dev msgHash => timestamp the cancellation was started at (0 = not requested).
    mapping(bytes32 msgHash => uint256 requestTime) public cancellationRequests;

    uint256 internal _nonce;

    // --- sendMessageToL2 recording (args verbatim) ---
    address public lastSender;
    uint256 public lastToAddress;
    uint256 public lastSelector;
    uint256[] internal _lastPayload;
    uint256 public lastFee;
    uint256 public sendCalls;

    // --- consumeMessageFromL2 recording ---
    uint256 public lastConsumedFrom;
    address public lastConsumer;
    bytes32 public lastConsumedMsgHash;
    uint256 public consumeCalls;

    function getMaxL1MsgFee() external pure returns (uint256) {
        return MAX_L1_MSG_FEE;
    }

    function messageCancellationDelay() external pure returns (uint256) {
        return CANCELLATION_DELAY;
    }

    function l2ToL1Messages(bytes32 msgHash) external view returns (uint256) {
        return _l2ToL1Messages[msgHash];
    }

    function lastPayload() external view returns (uint256[] memory) {
        return _lastPayload;
    }

    /// @notice Upstream L1 -> L2 message hash formula.
    function l1ToL2MsgHash(
        address fromAddress,
        uint256 toAddress,
        uint256 selector,
        uint256[] calldata payload,
        uint256 nonce
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(uint256(uint160(fromAddress)), toAddress, nonce, selector, payload.length, payload)
        );
    }

    /// @notice Upstream L2 -> L1 message hash formula (keys the consumable counter).
    function l2ToL1MsgHash(uint256 fromAddress, address toAddress, uint256[] memory payload)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(fromAddress, uint256(uint160(toAddress)), payload.length, payload));
    }

    /// @notice Test hook: loads a consumable L2 -> L1 message addressed to `toAddress` (call N times for N
    ///         copies of the same message — the counter semantics under test).
    function mockSendMessageFromL2(uint256 fromAddress, address toAddress, uint256[] calldata payload) external {
        _l2ToL1Messages[l2ToL1MsgHash(fromAddress, toAddress, payload)] += 1;
    }

    function sendMessageToL2(uint256 toAddress, uint256 selector, uint256[] calldata payload)
        external
        payable
        returns (bytes32 msgHash, uint256 nonce)
    {
        require(msg.value > 0, "L1_MSG_FEE_MUST_BE_GREATER_THAN_0");
        require(msg.value <= MAX_L1_MSG_FEE, "MAX_L1_MSG_FEE_EXCEEDED");
        require(toAddress < FIELD_PRIME, "OUT_OF_BOUND_TO_ADDRESS");
        require(selector < FIELD_PRIME, "OUT_OF_BOUND_SELECTOR");
        for (uint256 i; i < payload.length; ++i) {
            require(payload[i] < FIELD_PRIME, "OUT_OF_BOUND_PAYLOAD");
        }

        nonce = _nonce++;
        msgHash = l1ToL2MsgHash(msg.sender, toAddress, selector, payload, nonce);
        l1ToL2Messages[msgHash] = msg.value + 1;

        lastSender = msg.sender;
        lastToAddress = toAddress;
        lastSelector = selector;
        _lastPayload = payload;
        lastFee = msg.value;
        ++sendCalls;
    }

    function consumeMessageFromL2(uint256 fromAddress, uint256[] calldata payload) external returns (bytes32 msgHash) {
        msgHash = l2ToL1MsgHash(fromAddress, msg.sender, payload);
        require(_l2ToL1Messages[msgHash] > 0, "INVALID_MESSAGE_TO_CONSUME");
        _l2ToL1Messages[msgHash] -= 1;

        lastConsumedFrom = fromAddress;
        lastConsumer = msg.sender;
        lastConsumedMsgHash = msgHash;
        ++consumeCalls;
    }

    /// @dev The hash derives from `msg.sender`, so only the original L1 sender can start a cancellation
    ///      (a foreign caller lands on an unknown hash => `NO_MESSAGE_TO_CANCEL`), like upstream.
    function startL1ToL2MessageCancellation(
        uint256 toAddress,
        uint256 selector,
        uint256[] calldata payload,
        uint256 nonce
    ) external returns (bytes32 msgHash) {
        msgHash = l1ToL2MsgHash(msg.sender, toAddress, selector, payload, nonce);
        require(l1ToL2Messages[msgHash] > 0, "NO_MESSAGE_TO_CANCEL");
        cancellationRequests[msgHash] = block.timestamp;
    }

    /// @dev Sender-only (hash derives from `msg.sender`) + delay-enforced, like upstream. The escrowed fee is
    ///      NOT refunded — the message entry is simply zeroed.
    function cancelL1ToL2Message(uint256 toAddress, uint256 selector, uint256[] calldata payload, uint256 nonce)
        external
        returns (bytes32 msgHash)
    {
        msgHash = l1ToL2MsgHash(msg.sender, toAddress, selector, payload, nonce);
        require(l1ToL2Messages[msgHash] != 0, "NO_MESSAGE_TO_CANCEL");
        uint256 requestTime = cancellationRequests[msgHash];
        require(requestTime != 0, "MESSAGE_CANCELLATION_NOT_REQUESTED");
        require(block.timestamp >= requestTime + CANCELLATION_DELAY, "MESSAGE_CANCELLATION_NOT_ALLOWED_YET");
        l1ToL2Messages[msgHash] = 0;
    }
}
