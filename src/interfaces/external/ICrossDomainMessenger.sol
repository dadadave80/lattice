// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ICrossDomainMessenger (OP Stack, canonical L1<->L2) — vendored subset
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Minimal vendored subset of the canonical OP Stack `CrossDomainMessenger` — the CANONICAL L1<->L2
///         messenger (`L1CrossDomainMessenger` on L1, `L2CrossDomainMessenger` predeploy on L2) that carries
///         deposits (L1->L2) and withdrawals (L2->L1). `sendMessage` enqueues an outbound message to the paired
///         domain; the paired messenger delivers it by CALLing `_target` with `_message`, exposing the
///         authenticated counterpart sender via `xDomainMessageSender` for the duration of that call.
/// @dev VERIFIED minimal canonical OP L1<->L2 messenger interface — canonical source:
///      `ethereum-optimism/optimism` `packages/contracts-bedrock/.../universal/CrossDomainMessenger.sol` (MIT).
///      Signatures vendored VERBATIM (not invented) and re-declared at pragma `^0.8.30` — do NOT add an
///      `optimism` dependency. The L2 predeploy lives at a fixed address on every OP Stack chain:
///      `L2_CROSS_DOMAIN_MESSENGER = 0x4200000000000000000000000000000000000007`.
/// @dev NOTE: L2->L1 (withdrawal) messages finalize only AFTER the withdrawal challenge window; that timing is
///      handled off-chain by the messenger / portal and is invisible to this adapter, which is direction-agnostic.
/// @custom:lattice-source Optimism
interface ICrossDomainMessenger {
    /// @notice Sends a message to `_target` on the paired (other) domain, relayed by the counterpart messenger.
    /// @param _target      Target contract/wallet on the other domain.
    /// @param _message     Message payload to call `_target` with.
    /// @param _minGasLimit Minimum gas limit the message is relayed with on the other domain.
    /// @dev VOID — the canonical messenger returns nothing (the message hash is derived off-chain / from events).
    function sendMessage(address _target, bytes calldata _message, uint32 _minGasLimit) external payable;

    /// @notice The authenticated counterpart sender of the message currently being relayed (INVERTED AUTH: read
    ///         in the `_target`'s context during delivery). Equals a sentinel when no message is being relayed.
    function xDomainMessageSender() external view returns (address);

    /// @notice The messenger on the paired domain that this messenger sends to / receives from.
    function otherMessenger() external view returns (ICrossDomainMessenger);

    /// @notice Whether a message (by hash) has already been successfully relayed (self-dedup / replay guard).
    function successfulMessages(bytes32) external view returns (bool);

    /// @notice The next message nonce this messenger will assign.
    function messageNonce() external view returns (uint256);

    /// @notice The version of the message encoding this messenger produces.
    function MESSAGE_VERSION() external view returns (uint16);
}
