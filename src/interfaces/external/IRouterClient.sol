// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Client} from "@lattice/interfaces/external/CCIPClient.sol";

/// @title IRouterClient (Chainlink CCIP) — vendored subset
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Minimal vendored subset of Chainlink CCIP's `IRouterClient`: the source-side `ccipSend`/`getFee`
///         surface used by {CCIPGatewayAdapter}. `getSupportedTokens` is intentionally omitted — upstream it
///         lives on `IEVM2AnyOnRampClient`, not here.
/// @dev Verified verbatim against `smartcontractkit/chainlink-ccip` @ `main` commit `828897a` (2026-06-24):
///      `chains/evm/contracts/interfaces/IRouterClient.sol`. Routes by `uint64` chain selector (NOT chainId).
///      `feeToken == address(0)` ⇒ pay native via `msg.value`; an ERC-20 fee token is pulled via the router.
/// @custom:lattice-source Chainlink
interface IRouterClient {
    /// @notice The destination chain selector is not configured / supported by the router.
    error UnsupportedDestinationChain(uint64 destChainSelector);

    /// @notice The fee-token amount supplied is below the quoted fee.
    error InsufficientFeeTokenAmount();

    /// @notice `msg.value` was supplied with an ERC-20 fee token, or mismatched the native fee.
    error InvalidMsgValue();

    /// @notice Whether the router has a configured route to `destChainSelector`.
    function isChainSupported(uint64 destChainSelector) external view returns (bool supported);

    /// @notice Quotes the fee (in the message's `feeToken`) for `message` to `destinationChainSelector`.
    /// @dev Must be quoted with the EXACT message later passed to {ccipSend} or the send may revert.
    function getFee(uint64 destinationChainSelector, Client.EVM2AnyMessage memory message)
        external
        view
        returns (uint256 fee);

    /// @notice Submits `message` to `destinationChainSelector`; returns the CCIP message id.
    function ccipSend(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message)
        external
        payable
        returns (bytes32);
}
