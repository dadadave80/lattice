// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StarknetGatewayAdapterLib} from "@lattice/crosschain/starknet/StarknetGatewayAdapterLib.sol";
import {IStarknetGatewayAdapter} from "@lattice/interfaces/crosschain/IStarknetGatewayAdapter.sol";

/// @title StarknetGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Starknet (https://github.com/starkware-libs/cairo-lang)
/// @notice L1-side (Ethereum-only) Starknet L1 <-> L2 connector facet: {sendMessage} escrows a non-refundable
///         fee and dispatches a felt-chunk-encoded payload to a registered L2 `l1_handler`;
///         {startCancellation}/{cancel} are the initiator-gated two-step cancellation of an in-flight message;
///         {consumeMessage} is the permissionless keeper-driven PULL of a trusted L2 sender's message from the
///         core. DELIBERATELY BESPOKE, not an `IERC7786GatewaySource` — the inbound path is a counter-based
///         pull (no message id), attributes cannot express the escrowed fee + cancellation lifecycle, and the
///         wire payload is a felt array (see {IStarknetGatewayAdapter}).
/// @dev Stateless delegator — logic/storage live in {StarknetGatewayAdapterLib}. The send/cancel/consume paths
///      are `nonReentrant`; cancellation authority is re-derived at the facet level because the DIAMOND is the
///      L1 sender on the Starknet core. FEE WARNING: the message fee is escrowed by Starknet and NEVER
///      refunded, cancellation included.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Starknet
contract StarknetGatewayAdapter is IStarknetGatewayAdapter {
    /// @inheritdoc IStarknetGatewayAdapter
    function sendMessage(bytes calldata recipient, bytes calldata payload)
        external
        payable
        virtual
        returns (bytes32 msgHash, uint256 nonce)
    {
        return StarknetGatewayAdapterLib.sendMessage(recipient, payload);
    }

    /// @inheritdoc IStarknetGatewayAdapter
    function startCancellation(bytes calldata recipient, uint256 selector, bytes calldata payload, uint256 nonce)
        external
        virtual
        returns (bytes32 msgHash)
    {
        return StarknetGatewayAdapterLib.startCancellation(recipient, selector, payload, nonce);
    }

    /// @inheritdoc IStarknetGatewayAdapter
    function cancel(bytes calldata recipient, uint256 selector, bytes calldata payload, uint256 nonce)
        external
        virtual
        returns (bytes32 msgHash)
    {
        return StarknetGatewayAdapterLib.cancel(recipient, selector, payload, nonce);
    }

    /// @inheritdoc IStarknetGatewayAdapter
    function consumeMessage(uint256 fromAddress, bytes calldata payload) external virtual returns (bytes32 msgHash) {
        return StarknetGatewayAdapterLib.consumeMessage(fromAddress, payload);
    }

    /// @inheritdoc IStarknetGatewayAdapter
    function registerL2Handler(uint256 l2Target, uint256 selector) external virtual {
        StarknetGatewayAdapterLib.registerL2Handler(l2Target, selector);
    }

    /// @inheritdoc IStarknetGatewayAdapter
    function setTrustedL2Sender(uint256 fromAddress, bool trusted) external virtual {
        StarknetGatewayAdapterLib.setTrustedL2Sender(fromAddress, trusted);
    }

    /// @inheritdoc IStarknetGatewayAdapter
    function starknetCore() external view virtual returns (address) {
        return StarknetGatewayAdapterLib.starknetCore();
    }

    /// @inheritdoc IStarknetGatewayAdapter
    function expectedChainReference() external view virtual returns (bytes memory) {
        return StarknetGatewayAdapterLib.expectedChainReference();
    }

    /// @inheritdoc IStarknetGatewayAdapter
    function l1HandlerSelector(uint256 l2Target) external view virtual returns (uint256) {
        return StarknetGatewayAdapterLib.l1HandlerSelector(l2Target);
    }

    /// @inheritdoc IStarknetGatewayAdapter
    function isTrustedL2Sender(uint256 fromAddress) external view virtual returns (bool) {
        return StarknetGatewayAdapterLib.isTrustedL2Sender(fromAddress);
    }

    /// @inheritdoc IStarknetGatewayAdapter
    function initiatorOf(bytes32 msgHash) external view virtual returns (address) {
        return StarknetGatewayAdapterLib.initiatorOf(msgHash);
    }

    /// @inheritdoc IStarknetGatewayAdapter
    function starknetSelector(string calldata name) external pure virtual returns (uint256) {
        return StarknetGatewayAdapterLib.starknetSelector(name);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect StarknetGatewayAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `cancel(bytes,uint256,bytes,uint256)` 0x71dcb2b0
    ///      `consumeMessage(uint256,bytes)` 0x367bd9dd
    ///      `expectedChainReference()` 0x743bb3f6
    ///      `initiatorOf(bytes32)` 0x5b8cbad8
    ///      `isTrustedL2Sender(uint256)` 0x3984b96c
    ///      `l1HandlerSelector(uint256)` 0xc9aacd1d
    ///      `registerL2Handler(uint256,uint256)` 0x3b70379a
    ///      `sendMessage(bytes,bytes)` 0x48e6fa23
    ///      `setTrustedL2Sender(uint256,bool)` 0x92126474
    ///      `starknetCore()` 0x39e730ab
    ///      `starknetSelector(string)` 0xeafe2ebf
    ///      `startCancellation(bytes,uint256,bytes,uint256)` 0xd75ed921
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors =
        hex"71dcb2b0367bd9dd743bb3f65b8cbad83984b96cc9aacd1d3b70379a48e6fa239212647439e730abeafe2ebfd75ed921";
    }
}
