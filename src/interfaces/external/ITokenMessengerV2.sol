// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

/// @title ITokenMessengerV2
/// @author Vendored minimal subset of Circle's CCTP v2 `TokenMessengerV2`
///         (https://github.com/circlefin/evm-cctp-contracts). Upstream is Apache-2.0 and compiled at
///         Solidity 0.7.6 — this subset is REDECLARED at pragma ^0.8.30. Only the `depositForBurn` method the
///         {CCTPBridgeAdapter} calls is re-declared; do NOT add an evm-cctp-contracts dependency.
/// @notice Source-side entrypoint of CCTP v2: burns `amount` of `burnToken` (USDC) on the local chain and
///         emits the burn message an off-chain Circle attestation service (Iris) later attests for minting on
///         the destination domain. CCTP is a TOKEN BRIDGE, not an ERC-7786 message gateway.
interface ITokenMessengerV2 {
    /// @notice Burns `amount` of `burnToken` and signals a mint of the same amount on `destinationDomain`.
    /// @param amount               Amount of `burnToken` to burn (pulled from the caller — the adapter).
    /// @param destinationDomain    CCTP domain id of the destination chain (admin-registered, e.g. Eth 0).
    /// @param mintRecipient        Recipient on the destination domain, as a right-aligned `bytes32`.
    /// @param burnToken            Local token to burn (USDC).
    /// @param destinationCaller    If non-zero, the only address permitted to call `receiveMessage` on the
    ///                             destination; `bytes32(0)` makes the mint permissionless.
    /// @param maxFee               Maximum fee (in `burnToken` units) payable to CCTP for the transfer.
    /// @param minFinalityThreshold Minimum finality (e.g. 1000 = standard, 2000 = fast) before attestation.
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external;
}
