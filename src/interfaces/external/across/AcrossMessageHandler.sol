// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title AcrossMessageHandler
/// @author Vendored minimal subset of Across's `AcrossMessageHandler` (https://github.com/across-protocol/contracts). Upstream is MIT.
/// @notice Implemented by any contract that expects to receive messages from the Across v3 SpokePool: when a
///         deposit carries a non-empty `message`, the SpokePool calls `handleV3AcrossMessage` on the RECIPIENT
///         at fill time. Fills are relayer-pushed and optimistic — NOT yet UMA-finalized when this hook runs.
///         Upstream file: `contracts/interfaces/SpokePoolMessageHandler.sol`.
interface AcrossMessageHandler {
    /// @notice SpokePool-invoked delivery hook, called on the deposit's recipient at fill time.
    /// @param tokenSent The destination-chain token the relayer fronted to the recipient.
    /// @param amount    The `outputAmount` of `tokenSent` the recipient received.
    /// @param relayer   The relayer that filled the deposit (fronting its own funds).
    /// @param message   The deposit's `message` bytes, verbatim.
    function handleV3AcrossMessage(address tokenSent, uint256 amount, address relayer, bytes memory message) external;
}
