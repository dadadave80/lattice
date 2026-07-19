// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IMessageRecipient (Hyperlane message recipient) — vendored subset
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Vendored minimal subset of Hyperlane's `IMessageRecipient` (https://github.com/hyperlane-xyz/hyperlane-monorepo). Upstream is MIT OR Apache-2.0.
/// @notice The delivery callback the Hyperlane Mailbox invokes on the recipient at `process` time. PAYABLE
///         upstream — implementers that never expect value-bearing messages must guard `msg.value` themselves.
/// @dev Verified verbatim against `hyperlane-xyz/hyperlane-monorepo` (MIT OR Apache-2.0):
///      `solidity/contracts/interfaces/IMessageRecipient.sol`. Re-declared at pragma `^0.8.30` — do NOT add
///      a hyperlane-monorepo dependency.
/// @custom:lattice-source Hyperlane
interface IMessageRecipient {
    /// @notice Handles a Hyperlane message delivered by the local Mailbox.
    /// @param _origin The origin Hyperlane domain of the message.
    /// @param _sender The 32-byte message sender address on `_origin`.
    /// @param _message The raw message body.
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _message) external payable;
}
