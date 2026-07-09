// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IMailbox (Hyperlane Mailbox) — vendored subset
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Vendored minimal subset of Hyperlane's `IMailbox` (https://github.com/hyperlane-xyz/hyperlane-monorepo). Upstream is MIT OR Apache-2.0.
/// @notice Minimal vendored subset of the Hyperlane Mailbox: both `dispatch` overloads (default-hook and
///         default-hook-with-metadata) with their matching `quoteDispatch` views, plus the `delivered` replay
///         map and `localDomain` reads. Hyperlane routes by `uint32` domain (usually — but NOT guaranteed —
///         equal to the EVM chainId) and 32-byte recipient addresses.
/// @dev Verified verbatim against `hyperlane-xyz/hyperlane-monorepo` (MIT OR Apache-2.0):
///      `solidity/contracts/interfaces/IMailbox.sol`. Re-declared at pragma `^0.8.30` — do NOT add a
///      hyperlane-monorepo dependency. The `IPostDispatchHook` / `IInterchainSecurityModule` accessors and
///      custom-hook overloads are deliberately omitted (v1 uses the Mailbox DEFAULT ISM and default hook).
/// @custom:lattice-source Hyperlane
interface IMailbox {
    /// @notice This mailbox's Hyperlane domain (usually the EVM chainId, but never guaranteed).
    function localDomain() external view returns (uint32);

    /// @notice Whether `messageId` was already processed on this mailbox (the protocol-level replay guard —
    ///         `process` reverts on redelivery).
    function delivered(bytes32 messageId) external view returns (bool);

    /// @notice Dispatches `messageBody` to `recipientAddress` on `destinationDomain` via the default hook.
    function dispatch(uint32 destinationDomain, bytes32 recipientAddress, bytes calldata messageBody)
        external
        payable
        returns (bytes32 messageId);

    /// @notice Quotes the fee of the 3-arg `dispatch` overload.
    function quoteDispatch(uint32 destinationDomain, bytes32 recipientAddress, bytes calldata messageBody)
        external
        view
        returns (uint256 fee);

    /// @notice Dispatches `body` to `recipientAddress` on `destinationDomain`, passing `defaultHookMetadata`
    ///         (StandardHookMetadata: variant 1 || msgValue || gasLimit || refundAddress) to the default hook.
    function dispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata body,
        bytes calldata defaultHookMetadata
    ) external payable returns (bytes32 messageId);

    /// @notice Quotes the fee of the 4-arg `dispatch` overload.
    function quoteDispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody,
        bytes calldata defaultHookMetadata
    ) external view returns (uint256 fee);
}
