// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice A cross-chain message identifier, as emitted/consumed by the OP Superchain interop messaging layer.
///         Uniquely locates the log that authorized a message on the source chain.
/// @dev Verbatim mirror of the canonical `Identifier` struct.
struct Identifier {
    address origin;
    uint256 blockNumber;
    uint256 logIndex;
    uint256 timestamp;
    uint256 chainId;
}

/// @title IL2ToL2CrossDomainMessenger (OP Superchain) — vendored subset
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Vendored minimal subset of Optimism's `L2ToL2CrossDomainMessenger` (https://github.com/ethereum-optimism/optimism). Upstream is MIT.
/// @notice Minimal vendored subset of the OP Superchain `L2ToL2CrossDomainMessenger` predeploy — the
///         same-domain (L2→L2) messenger that lets contracts on one Superchain chain call contracts on another,
///         routed purely by destination `chainId`. `sendMessage` enqueues an outbound message; `relayMessage`
///         (invoked by a relayer on the destination chain) executes it against the `_target`, exposing the
///         authenticated cross-domain `(sender, source)` via `crossDomainMessageContext` for the duration of the
///         call.
/// @dev VERIFIED minimal OP Superchain interface subset — canonical:
///      `ethereum-optimism/optimism` `packages/contracts-bedrock/.../L2ToL2CrossDomainMessenger.sol` (MIT).
///      Signatures vendored VERBATIM (not invented) and re-declared at pragma `^0.8.30` — do NOT add an
///      `optimism` dependency. The predeploy lives at a fixed address on every OP Superchain chain:
///      `L2_TO_L2_CROSS_DOMAIN_MESSENGER = 0x4200000000000000000000000000000000000023`.
/// @dev NOTE: Superchain interop is PRE-MAINNET. Both the predeploy address AND the message encoding MUST be
///      re-verified against the then-current `contracts-bedrock` release before ANY production deploy.
/// @custom:lattice-source Optimism
interface IL2ToL2CrossDomainMessenger {
    /// @notice Sends a message to `_target` on chain `_destination`, to be relayed by `relayMessage`.
    /// @param _destination Destination chain id.
    /// @param _target      Target contract/wallet on the destination chain.
    /// @param _message     Message payload to call `_target` with.
    /// @return messageHash_ The hash of the message, used to track its status.
    function sendMessage(uint256 _destination, address _target, bytes calldata _message)
        external
        returns (bytes32 messageHash_);

    /// @notice Relays a message that was sent by the source-chain `L2ToL2CrossDomainMessenger`.
    /// @param _id          Identifier of the `SentMessage` event log to relay.
    /// @param _sentMessage The message payload (the ABI-encoded `SentMessage` event data).
    /// @return returnData_ The return data of the target call.
    function relayMessage(Identifier calldata _id, bytes calldata _sentMessage)
        external
        payable
        returns (bytes memory returnData_);

    /// @notice Retrieves the sender AND source of the message currently being relayed (in the target's context).
    /// @return sender_ The account (on the source chain) that sent the message.
    /// @return source_ The chain id of the source chain.
    function crossDomainMessageContext() external view returns (address sender_, uint256 source_);

    /// @notice Retrieves the sender of the message currently being relayed.
    function crossDomainMessageSender() external view returns (address sender_);

    /// @notice Retrieves the source chain id of the message currently being relayed.
    function crossDomainMessageSource() external view returns (uint256 source_);

    /// @notice Whether a message (by hash) has already been successfully relayed (self-dedup / replay guard).
    function successfulMessages(bytes32) external view returns (bool);

    /// @notice The version of the message encoding this messenger produces.
    function messageVersion() external view returns (uint16);

    /// @notice The next message nonce this messenger will assign.
    function messageNonce() external view returns (uint256);
}
