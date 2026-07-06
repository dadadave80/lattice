// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Options controlling the ZetaChain revert/abort flow for a cross-chain call.
/// @dev Verbatim mirror of the canonical `RevertOptions` struct (`zeta-chain/protocol-contracts`
///      `contracts/Revert.sol`, MIT).
/// @param revertAddress    Address to receive the revert on the source chain.
/// @param callOnRevert     Whether the `onRevert` hook should be called.
/// @param abortAddress     Address to receive funds if the message is aborted.
/// @param revertMessage    Arbitrary data sent back in `onRevert`.
/// @param onRevertGasLimit Gas limit for the revert tx (unused on GatewayZEVM methods).
struct RevertOptions {
    address revertAddress;
    bool callOnRevert;
    address abortAddress;
    bytes revertMessage;
    uint256 onRevertGasLimit;
}

/// @notice Context passed by the ZetaChain `GatewayEVM` to a `Callable` receiver on inbound delivery.
/// @dev Verbatim mirror of the canonical `MessageContext` struct
///      (`zeta-chain/protocol-contracts` `contracts/evm/interfaces/IGatewayEVM.sol`, MIT). NOTE: `sender` is the
///      ZEVM universal-app contract that terminated the hub route — NOT a source EVM chainId or the original EOA.
/// @param sender The ZEVM universal-app address that initiated the outbound call to this chain.
struct MessageContext {
    address sender;
}

/// @title IGatewayEVM (ZetaChain) — vendored subset
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Vendored minimal subset of ZetaChain's `IGatewayEVM` (https://github.com/zeta-chain/protocol-contracts). Upstream is MIT.
/// @notice Minimal vendored subset of the ZetaChain `GatewayEVM` — the DEPLOYED (per-connected-chain) gateway that
///         relays a message to a ZEVM universal app (the hub). `call` dispatches an outbound arbitrary-message
///         call (native `msg.value` is the messaging fee); the ZetaChain TSS/observer set later invokes the
///         destination-chain `Callable.onCall` to deliver an inbound message.
/// @dev VERIFIED minimal ZetaChain interface subset — canonical: `zeta-chain/protocol-contracts`
///      `contracts/evm/interfaces/IGatewayEVM.sol` + `contracts/Revert.sol` (both MIT,
///      `Copyright (c) 2022 Meta Protocol, Inc.`). Signatures vendored VERBATIM (not invented) and re-declared at
///      pragma `^0.8.30` (canonical is `0.8.26`) — do NOT add a `zeta-chain/protocol-contracts` dependency. The
///      `GatewayEVM` is a DEPLOYED contract whose address varies per connected chain (NOT a fixed predeploy).
/// @custom:lattice-source ZetaChain
interface IGatewayEVM {
    /// @notice Sends an arbitrary-message cross-chain call, routed via ZetaChain to `receiver` (the ZEVM universal
    ///         app / hub). Any `msg.value` is forwarded as the native messaging fee.
    /// @param receiver      The recipient of the call on ZetaChain (the ZEVM universal app / hub route terminus).
    /// @param payload       The calldata to deliver.
    /// @param revertOptions Options controlling the revert/abort flow on failure.
    function call(address receiver, bytes calldata payload, RevertOptions calldata revertOptions) external payable;
}

/// @title Callable (ZetaChain) — vendored subset
/// @notice The ZetaChain inbound receiver hook. The `GatewayEVM` (invoked by the ZetaChain TSS/observer set)
///         calls `onCall` on the destination-chain receiver to deliver a message.
/// @dev Verbatim mirror of the canonical `Callable` interface (`zeta-chain/protocol-contracts`
///      `contracts/evm/interfaces/IGatewayEVM.sol`, MIT).
interface Callable {
    /// @notice Inbound delivery hook invoked by the `GatewayEVM` on message arrival.
    /// @param context The ZetaChain message context (`sender` = the ZEVM universal app that originated the call).
    /// @param message The delivered message payload.
    /// @return The receiver's result bytes (may be empty).
    function onCall(MessageContext calldata context, bytes calldata message) external payable returns (bytes memory);
}
