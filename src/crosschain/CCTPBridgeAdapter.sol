// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CCTPBridgeAdapterLib} from "@lattice/crosschain/libraries/CCTPBridgeAdapterLib.sol";
import {ICCTPBridgeAdapter} from "@lattice/interfaces/crosschain/ICCTPBridgeAdapter.sol";

/// @title CCTPBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Circle CCTP v2 (https://github.com/circlefin/evm-cctp-contracts)
/// @notice Circle CCTP v2 USDC token-bridge facet: `depositForBurn` burns USDC on this chain toward an
///         ERC-7930 recipient, `relayMessage` forwards an Iris-attested inbound message to the CCTP
///         transmitter for minting. CCTP is a TOKEN BRIDGE (burn-and-mint), NOT an ERC-7786 message gateway —
///         this facet is deliberately not an `IERC7786GatewaySource` and never routes through OpenBridge.
/// @dev Stateless delegator — logic/storage live in {CCTPBridgeAdapterLib}. The outbound burn is `nonReentrant`
///      with strict CEI and exact-amount approval hygiene; the inbound relay is a PERMISSIONLESS passthrough
///      (trust roots in Circle's Iris attester set + denylist, not this contract).
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Circle
contract CCTPBridgeAdapter is ICCTPBridgeAdapter {
    /// @inheritdoc ICCTPBridgeAdapter
    function depositForBurn(uint256 amount, bytes calldata recipient) external virtual {
        CCTPBridgeAdapterLib.depositForBurn(amount, recipient);
    }

    /// @inheritdoc ICCTPBridgeAdapter
    function relayMessage(bytes calldata message, bytes calldata attestation) external virtual {
        CCTPBridgeAdapterLib.relayMessage(message, attestation);
    }

    /// @inheritdoc ICCTPBridgeAdapter
    function registerChainDomain(uint256 chainId, uint32 domain) external virtual {
        CCTPBridgeAdapterLib.registerChainDomain(chainId, domain);
    }

    /// @inheritdoc ICCTPBridgeAdapter
    function configureDomain(uint32 domain, uint256 maxFee, uint32 minFinalityThreshold, bytes32 destinationCaller)
        external
        virtual
    {
        CCTPBridgeAdapterLib.configureDomain(domain, maxFee, minFinalityThreshold, destinationCaller);
    }

    /// @inheritdoc ICCTPBridgeAdapter
    function tokenMessenger() external view virtual returns (address) {
        return CCTPBridgeAdapterLib.tokenMessenger();
    }

    /// @inheritdoc ICCTPBridgeAdapter
    function messageTransmitter() external view virtual returns (address) {
        return CCTPBridgeAdapterLib.messageTransmitter();
    }

    /// @inheritdoc ICCTPBridgeAdapter
    function usdc() external view virtual returns (address) {
        return CCTPBridgeAdapterLib.usdc();
    }

    /// @inheritdoc ICCTPBridgeAdapter
    function getDomain(uint256 chainId) external view virtual returns (uint32) {
        return CCTPBridgeAdapterLib.getDomain(chainId);
    }

    /// @inheritdoc ICCTPBridgeAdapter
    function domainOwner(uint32 domain) external view virtual returns (uint256) {
        return CCTPBridgeAdapterLib.domainOwner(domain);
    }

    /// @inheritdoc ICCTPBridgeAdapter
    function isChainRegistered(uint256 chainId) external view virtual returns (bool) {
        return CCTPBridgeAdapterLib.isChainRegistered(chainId);
    }

    /// @inheritdoc ICCTPBridgeAdapter
    function getDomainConfig(uint32 domain)
        external
        view
        virtual
        returns (uint256 maxFee, uint32 minFinalityThreshold, bytes32 destinationCaller)
    {
        return CCTPBridgeAdapterLib.getDomainConfig(domain);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect CCTPBridgeAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `configureDomain(uint32,uint256,uint32,bytes32)` 0x4736cc95
    ///      `depositForBurn(uint256,bytes)` 0x3d8f1160
    ///      `domainOwner(uint32)` 0x3f1f7a9f
    ///      `getDomain(uint256)` 0x1a7a98e2
    ///      `getDomainConfig(uint32)` 0xf7d38221
    ///      `isChainRegistered(uint256)` 0xb9e06402
    ///      `messageTransmitter()` 0x7b04c181
    ///      `registerChainDomain(uint256,uint32)` 0xa3e6f535
    ///      `relayMessage(bytes,bytes)` 0x29351b45
    ///      `tokenMessenger()` 0x46117830
    ///      `usdc()` 0x3e413bee
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"4736cc953d8f11603f1f7a9f1a7a98e2f7d38221b9e064027b04c181a3e6f53529351b45461178303e413bee";
    }
}
