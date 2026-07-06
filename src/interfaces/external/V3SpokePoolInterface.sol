// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title V3SpokePoolInterface
/// @author Vendored minimal subset of Across's `V3SpokePoolInterface` (https://github.com/across-protocol/contracts). Upstream is MIT.
/// @notice Source-side entrypoint of the Across v3 intent/optimistic bridge: `deposit` escrows `inputAmount` of
///         `inputToken` on this chain and emits the intent a relayer may fill on `destinationChainId` by fronting
///         `outputAmount` of `outputToken` to `recipient` (the relayer is later reimbursed via UMA optimistic
///         settlement). Only the canonical `bytes32` deposit entrypoint the {AcrossBridgeAdapter} calls is
///         re-declared (the legacy address-based `depositV3` upstream is a thin wrapper casting into this); do
///         NOT add an across-protocol/contracts dependency.
interface V3SpokePoolInterface {
    /// @notice Escrows `inputAmount` of `inputToken` (pulled from the caller) as an Across v3 deposit intent.
    /// @param depositor            Who made the deposit AND who Across refunds ON THIS CHAIN if no relayer fills
    ///                             before `fillDeadline` (also the only party able to speed up the deposit).
    ///                             Must be a valid EVM address (top 12 bytes zero) despite the `bytes32` type.
    /// @param recipient            Recipient on the destination chain, right-aligned `bytes32` (non-EVM capable).
    /// @param inputToken           Token escrowed on THIS chain, right-aligned `bytes32`. `msg.value` must be 0
    ///                             unless this is the wrapped native token.
    /// @param outputToken          Token the relayer fronts on the destination chain; must not be `bytes32(0)`.
    /// @param inputAmount          Amount of `inputToken` pulled from the caller via `safeTransferFrom`.
    /// @param outputAmount         Amount of `outputToken` the recipient receives at fill time.
    /// @param destinationChainId   Across chain id of the destination chain.
    /// @param exclusiveRelayer     Only relayer allowed to fill before the exclusivity deadline (`bytes32(0)` =
    ///                             no exclusivity; required non-zero when `exclusivityParameter` is set).
    /// @param quoteTimestamp       Quote-API timestamp the LP fee is priced at; must be within the SpokePool's
    ///                             `depositQuoteTimeBuffer` of the current time.
    /// @param fillDeadline         Destination-chain timestamp after which the deposit can no longer be filled
    ///                             (and gets refunded to `depositor`); bounded by `fillDeadlineBuffer`.
    /// @param exclusivityParameter 0 = no exclusivity; <= the max period = offset added to `block.timestamp`;
    ///                             otherwise interpreted as an absolute exclusivity-deadline timestamp.
    /// @param message              Arbitrary bytes delivered to the recipient via `handleV3AcrossMessage` at fill
    ///                             time when non-empty.
    function deposit(
        bytes32 depositor,
        bytes32 recipient,
        bytes32 inputToken,
        bytes32 outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        bytes32 exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityParameter,
        bytes calldata message
    ) external payable;
}
