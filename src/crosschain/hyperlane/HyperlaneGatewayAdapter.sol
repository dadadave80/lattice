// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HyperlaneGatewayAdapterLib} from "@lattice/crosschain/hyperlane/HyperlaneGatewayAdapterLib.sol";
import {IHyperlaneGatewayAdapter} from "@lattice/interfaces/crosschain/IHyperlaneGatewayAdapter.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {IMessageRecipient} from "@lattice/interfaces/external/hyperlane/IMessageRecipient.sol";

/// @title HyperlaneGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Hyperlane (https://github.com/hyperlane-xyz/hyperlane-monorepo)
/// @notice ERC-7786 cross-chain gateway facet over the Hyperlane Mailbox. `sendMessage` quotes + dispatches a
///         Hyperlane message via the Mailbox's 4-arg `dispatch` (default hook + synthesized
///         StandardHookMetadata); `handle` is the Mailbox's delivery callback. EVM chains only.
/// @dev Stateless delegator — logic/storage live in {HyperlaneGatewayAdapterLib}. Hyperlane routes by `uint32`
///      domain (usually the EVM chainId but NOT guaranteed — the lib holds an admin-registered chainId ⇄
///      domain map + a 32-byte trusted remote per chain); the Mailbox-gated `handle` is the inbound analogue
///      of LayerZero's `lzReceive` / CCIP's `ccipReceive`. Implements {IMessageRecipient} so the Mailbox can
///      deliver messages at `process` time. v1 uses the Mailbox DEFAULT ISM — the facet deliberately does NOT
///      implement `ISpecifiesInterchainSecurityModule`; pinning a Lattice-custom ISM by adding
///      `interchainSecurityModule()` later is a compatible additive follow-up.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Hyperlane
contract HyperlaneGatewayAdapter is IERC7786GatewaySource, IMessageRecipient, IHyperlaneGatewayAdapter {
    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        external
        payable
        virtual
        returns (bytes32)
    {
        return HyperlaneGatewayAdapterLib.sendMessage(recipient, payload, attributes);
    }

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 selector) external pure virtual returns (bool) {
        return HyperlaneGatewayAdapterLib.supportsAttribute(selector);
    }

    /// @inheritdoc IMessageRecipient
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _message) external payable virtual {
        HyperlaneGatewayAdapterLib.handle(_origin, _sender, _message);
    }

    /// @inheritdoc IHyperlaneGatewayAdapter
    function mailbox() external view virtual returns (address) {
        return HyperlaneGatewayAdapterLib.mailbox();
    }

    /// @inheritdoc IHyperlaneGatewayAdapter
    function domainOf(uint256 chainId) external view virtual returns (uint32) {
        return HyperlaneGatewayAdapterLib.domainOf(chainId);
    }

    /// @inheritdoc IHyperlaneGatewayAdapter
    function chainIdOf(uint32 domain) external view virtual returns (uint256) {
        return HyperlaneGatewayAdapterLib.chainIdOf(domain);
    }

    /// @inheritdoc IHyperlaneGatewayAdapter
    function trustedRemoteOf(uint256 chainId) external view virtual returns (bytes32) {
        return HyperlaneGatewayAdapterLib.trustedRemoteOf(chainId);
    }

    /// @inheritdoc IHyperlaneGatewayAdapter
    function destGasLimitOf(uint256 chainId) external view virtual returns (uint256) {
        return HyperlaneGatewayAdapterLib.destGasLimitOf(chainId);
    }

    /// @inheritdoc IHyperlaneGatewayAdapter
    function quoteFee(bytes calldata recipient, bytes calldata payload) external view virtual returns (uint256) {
        return HyperlaneGatewayAdapterLib.quoteFee(recipient, payload);
    }

    /// @inheritdoc IHyperlaneGatewayAdapter
    function registerDomain(uint256 chainId, uint32 domain) external virtual {
        HyperlaneGatewayAdapterLib.registerDomain(chainId, domain);
    }

    /// @inheritdoc IHyperlaneGatewayAdapter
    function registerRemote(uint256 chainId, bytes32 remote) external virtual {
        HyperlaneGatewayAdapterLib.registerRemote(chainId, remote);
    }

    /// @inheritdoc IHyperlaneGatewayAdapter
    function configureDestination(uint256 chainId, uint256 gasLimit) external virtual {
        HyperlaneGatewayAdapterLib.configureDestination(chainId, gasLimit);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect HyperlaneGatewayAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `chainIdOf(uint32)` 0x97a21652
    ///      `configureDestination(uint256,uint256)` 0xcb21a740
    ///      `destGasLimitOf(uint256)` 0x2f85b407
    ///      `domainOf(uint256)` 0xc6c17ec0
    ///      `handle(uint32,bytes32,bytes)` 0x56d5d475
    ///      `mailbox()` 0xd5438eae
    ///      `quoteFee(bytes,bytes)` 0x58d14c04
    ///      `registerDomain(uint256,uint32)` 0x5be59524
    ///      `registerRemote(uint256,bytes32)` 0xe914f0f6
    ///      `sendMessage(bytes,bytes,bytes[])` 0xcdfe7f5c
    ///      `supportsAttribute(bytes4)` 0xdc680a0f
    ///      `trustedRemoteOf(uint256)` 0x3e56e39a
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors =
        hex"97a21652cb21a7402f85b407c6c17ec056d5d475d5438eae58d14c045be59524e914f0f6cdfe7f5cdc680a0f3e56e39a";
    }
}
