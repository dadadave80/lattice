// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC7786MessageHandler
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Handler invoked by the {CrosschainLink} facet for a validated inbound ERC-7786 message,
///         routed by the leading 4-byte tag of the payload.
/// @dev A handler is registered per tag via `ICrosschainLink.setHandler`. The facet authenticates the
///      gateway + source and de-duplicates `receiveId` BEFORE calling `processMessage`, so handlers may
///      assume the message is authentic and fresh. Handlers MUST revert on failure — a silent return
///      marks the message processed and non-retryable (ERC-7786 at-most-once delivery).
interface IERC7786MessageHandler {
    /// @notice Process a validated, de-duplicated cross-chain message.
    /// @param receiveId The gateway-assigned unique message id (already checked for replay by the facet).
    /// @param sender    The ERC-7930 interoperable address of the source (includes the source chain).
    /// @param payload   The message payload with the leading 4-byte handler tag stripped.
    function processMessage(bytes32 receiveId, bytes calldata sender, bytes calldata payload) external;
}
