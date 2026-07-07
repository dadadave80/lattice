// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HyperlaneGatewayAdapterLib} from "@lattice/crosschain/libraries/HyperlaneGatewayAdapterLib.sol";
import {IHyperlaneGatewayAdapter} from "@lattice/interfaces/crosschain/IHyperlaneGatewayAdapter.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/IERC7786.sol";
import {IMessageRecipient} from "@lattice/interfaces/external/IMessageRecipient.sol";

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
}
