// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

/// @title IReceiverV2
/// @author Vendored minimal subset of Circle's CCTP v2 `MessageTransmitterV2`
///         (https://github.com/circlefin/evm-cctp-contracts). Upstream is Apache-2.0 and compiled at
///         Solidity 0.7.6 — this subset is REDECLARED at pragma ^0.8.30. Only the receive-side methods the
///         {CCTPBridgeAdapter} relays to are re-declared; do NOT add an evm-cctp-contracts dependency.
/// @notice Destination-side of CCTP v2: `receiveMessage` validates the Iris attestation over `message` and,
///         if valid, mints USDC DIRECTLY to the encoded recipient. It is PERMISSIONLESS unless the burn
///         specified a `destinationCaller` — the mint's trust root is the Circle attester set + denylist, not
///         the calling contract.
interface IReceiverV2 {
    /// @notice Verifies `attestation` over `message` and executes the message (mints USDC to the recipient).
    /// @param message     The CCTP message bytes emitted by the source `depositForBurn`.
    /// @param attestation The Iris attestation (attester signatures) over `message`.
    /// @return success    True if the message was received and executed.
    function receiveMessage(bytes calldata message, bytes calldata attestation) external returns (bool success);

    /// @notice The CCTP domain id of the chain this transmitter is deployed on.
    function localDomain() external view returns (uint32);
}
