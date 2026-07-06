// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {WormholeGatewayAdapterLib} from "@lattice/crosschain/libraries/WormholeGatewayAdapterLib.sol";
import {IWormholeGatewayAdapter} from "@lattice/interfaces/crosschain/IWormholeGatewayAdapter.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/IERC7786.sol";
import {IWormholeReceiver} from "@lattice/interfaces/external/IWormholeRelayer.sol";

/// @title WormholeGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin community-contracts `WormholeGatewayAdapter` (https://github.com/OpenZeppelin/openzeppelin-community-contracts, commit f7e5f08)
///         (https://github.com/OpenZeppelin/openzeppelin-community-contracts/blob/f7e5f08e8fd42023084eb41f4a992d7be897b915/contracts/crosschain/wormhole/WormholeGatewayAdapter.sol)
/// @notice Dual-mode ERC-7786 gateway facet over the Wormhole relayer. Two-phase send (pending +
///         `requestRelay`, or immediate via a `requestRelay` attribute); `receiveWormholeMessages` is the
///         relayer's delivery callback. EVM chains only.
/// @dev Stateless delegator — logic/storage live in {WormholeGatewayAdapterLib}. OZ's `immutable` relayer +
///      `Ownable` are converted to ERC-7201 storage + AccessControl; `BitMaps` replay → a plain mapping.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin
contract WormholeGatewayAdapter is IERC7786GatewaySource, IWormholeReceiver, IWormholeGatewayAdapter {
    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        external
        payable
        virtual
        returns (bytes32)
    {
        return WormholeGatewayAdapterLib.sendMessage(recipient, payload, attributes);
    }

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 selector) external pure virtual returns (bool) {
        return WormholeGatewayAdapterLib.supportsAttribute(selector);
    }

    /// @inheritdoc IWormholeReceiver
    function receiveWormholeMessages(
        bytes calldata payload,
        bytes[] calldata, /*additionalVaas*/
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable virtual {
        WormholeGatewayAdapterLib.receiveWormholeMessages(payload, sourceAddress, sourceChain, deliveryHash);
    }

    /// @inheritdoc IWormholeGatewayAdapter
    function requestRelay(bytes32 sendId, uint256 gasLimit, address refundRecipient) external payable virtual {
        WormholeGatewayAdapterLib.requestRelay(sendId, gasLimit, refundRecipient);
    }

    /// @inheritdoc IWormholeGatewayAdapter
    function relayer() external view virtual returns (address) {
        return WormholeGatewayAdapterLib.relayer();
    }

    /// @inheritdoc IWormholeGatewayAdapter
    function wormholeChainId() external view virtual returns (uint16) {
        return WormholeGatewayAdapterLib.wormholeChainId();
    }

    /// @inheritdoc IWormholeGatewayAdapter
    function getWormholeChain(uint256 chainId) external view virtual returns (uint16) {
        return WormholeGatewayAdapterLib.getWormholeChain(chainId);
    }

    /// @inheritdoc IWormholeGatewayAdapter
    function getChainId(uint16 wormhole) external view virtual returns (uint256) {
        return WormholeGatewayAdapterLib.getChainId(wormhole);
    }

    /// @inheritdoc IWormholeGatewayAdapter
    function getRemoteGateway(uint256 chainId) external view virtual returns (address) {
        return WormholeGatewayAdapterLib.getRemoteGateway(chainId);
    }

    /// @inheritdoc IWormholeGatewayAdapter
    function quoteRelay(bytes calldata recipient, uint256 gasLimit) external view virtual returns (uint256) {
        return WormholeGatewayAdapterLib.quoteRelay(recipient, gasLimit);
    }

    /// @inheritdoc IWormholeGatewayAdapter
    function registerChainEquivalence(uint256 chainId, uint16 wormhole) external virtual {
        WormholeGatewayAdapterLib.registerChainEquivalence(chainId, wormhole);
    }

    /// @inheritdoc IWormholeGatewayAdapter
    function registerRemoteGateway(uint256 chainId, address remote) external virtual {
        WormholeGatewayAdapterLib.registerRemoteGateway(chainId, remote);
    }
}
