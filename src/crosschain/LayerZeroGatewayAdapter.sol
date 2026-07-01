// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LayerZeroGatewayAdapterLib} from "@lattice/crosschain/libraries/LayerZeroGatewayAdapterLib.sol";
import {ILayerZeroGatewayAdapter} from "@lattice/interfaces/crosschain/ILayerZeroGatewayAdapter.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/IERC7786.sol";
import {Origin} from "@lattice/interfaces/external/ILayerZeroEndpointV2.sol";
import {ILayerZeroReceiver} from "@lattice/interfaces/external/ILayerZeroReceiver.sol";

/// @title LayerZeroGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice ERC-7786 cross-chain gateway facet over the LayerZero v2 EndpointV2 (OApp). `sendMessage` quotes +
///         dispatches a LayerZero message via the endpoint; `lzReceive` is the endpoint's delivery callback.
///         EVM chains only.
/// @dev Stateless delegator — logic/storage live in {LayerZeroGatewayAdapterLib}. LayerZero routes by `uint32`
///      endpoint id (the lib holds a chainId ⇄ eid map + a 32-byte trusted peer per chain); the endpoint-gated
///      `lzReceive` is the inbound analogue of CCIP's `ccipReceive` / Wormhole's `receiveWormholeMessages`.
///      Implements {ILayerZeroReceiver} (`lzReceive` / `allowInitializePath` / `nextNonce`) so the endpoint can
///      deliver messages and query the OApp's unordered-delivery / trusted-peer policy.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source LayerZero
contract LayerZeroGatewayAdapter is IERC7786GatewaySource, ILayerZeroReceiver, ILayerZeroGatewayAdapter {
    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        external
        payable
        virtual
        returns (bytes32)
    {
        return LayerZeroGatewayAdapterLib.sendMessage(recipient, payload, attributes);
    }

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 selector) external pure virtual returns (bool) {
        return LayerZeroGatewayAdapterLib.supportsAttribute(selector);
    }

    /// @inheritdoc ILayerZeroReceiver
    function lzReceive(Origin calldata origin, bytes32 guid, bytes calldata message, address, bytes calldata)
        external
        payable
        virtual
    {
        LayerZeroGatewayAdapterLib.lzReceive(origin, guid, message);
    }

    /// @inheritdoc ILayerZeroReceiver
    function allowInitializePath(Origin calldata origin) external view virtual returns (bool) {
        return LayerZeroGatewayAdapterLib.allowInitializePath(origin);
    }

    /// @inheritdoc ILayerZeroReceiver
    function nextNonce(uint32 eid, bytes32 sender) external pure virtual returns (uint64) {
        return LayerZeroGatewayAdapterLib.nextNonce(eid, sender);
    }

    /// @inheritdoc ILayerZeroGatewayAdapter
    function endpoint() external view virtual returns (address) {
        return LayerZeroGatewayAdapterLib.endpoint();
    }

    /// @inheritdoc ILayerZeroGatewayAdapter
    function getEid(uint256 chainId) external view virtual returns (uint32) {
        return LayerZeroGatewayAdapterLib.getEid(chainId);
    }

    /// @inheritdoc ILayerZeroGatewayAdapter
    function getChainId(uint32 eid) external view virtual returns (uint256) {
        return LayerZeroGatewayAdapterLib.getChainId(eid);
    }

    /// @inheritdoc ILayerZeroGatewayAdapter
    function getPeer(uint256 chainId) external view virtual returns (bytes32) {
        return LayerZeroGatewayAdapterLib.getPeer(chainId);
    }

    /// @inheritdoc ILayerZeroGatewayAdapter
    function getDestinationGas(uint256 chainId) external view virtual returns (uint128) {
        return LayerZeroGatewayAdapterLib.getDestinationGas(chainId);
    }

    /// @inheritdoc ILayerZeroGatewayAdapter
    function getDestinationMsgValue(uint256 chainId) external view virtual returns (uint128) {
        return LayerZeroGatewayAdapterLib.getDestinationMsgValue(chainId);
    }

    /// @inheritdoc ILayerZeroGatewayAdapter
    function quoteFee(bytes calldata recipient, bytes calldata payload) external view virtual returns (uint256) {
        return LayerZeroGatewayAdapterLib.quoteFee(recipient, payload);
    }

    /// @inheritdoc ILayerZeroGatewayAdapter
    function registerEid(uint256 chainId, uint32 eid) external virtual {
        LayerZeroGatewayAdapterLib.registerEid(chainId, eid);
    }

    /// @inheritdoc ILayerZeroGatewayAdapter
    function registerPeer(uint256 chainId, bytes32 peer) external virtual {
        LayerZeroGatewayAdapterLib.registerPeer(chainId, peer);
    }

    /// @inheritdoc ILayerZeroGatewayAdapter
    function configureDestination(uint256 chainId, uint128 gas, uint128 msgValue) external virtual {
        LayerZeroGatewayAdapterLib.configureDestination(chainId, gas, msgValue);
    }
}
