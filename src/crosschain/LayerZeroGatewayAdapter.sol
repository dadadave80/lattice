// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LayerZeroGatewayAdapterLib} from "@lattice/crosschain/libraries/LayerZeroGatewayAdapterLib.sol";
import {ILayerZeroGatewayAdapter} from "@lattice/interfaces/crosschain/ILayerZeroGatewayAdapter.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {Origin} from "@lattice/interfaces/external/layerzero/ILayerZeroEndpointV2.sol";
import {ILayerZeroReceiver} from "@lattice/interfaces/external/layerzero/ILayerZeroReceiver.sol";

/// @title LayerZeroGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from LayerZero v2 (https://github.com/LayerZero-Labs/LayerZero-v2)
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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect LayerZeroGatewayAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `allowInitializePath((uint32,bytes32,uint64))` 0xff7bd03d
    ///      `configureDestination(uint256,uint128,uint128)` 0xb3602f8d
    ///      `endpoint()` 0x5e280f11
    ///      `getChainId(uint32)` 0x94f79a53
    ///      `getDestinationGas(uint256)` 0x73ad8334
    ///      `getDestinationMsgValue(uint256)` 0x8c0b3902
    ///      `getEid(uint256)` 0x193dc209
    ///      `getPeer(uint256)` 0x67ebb6b2
    ///      `lzReceive((uint32,bytes32,uint64),bytes32,bytes,address,bytes)` 0x13137d65
    ///      `nextNonce(uint32,bytes32)` 0x7d25a05e
    ///      `quoteFee(bytes,bytes)` 0x58d14c04
    ///      `registerEid(uint256,uint32)` 0x5d6e12a2
    ///      `registerPeer(uint256,bytes32)` 0x24ac554d
    ///      `sendMessage(bytes,bytes,bytes[])` 0xcdfe7f5c
    ///      `supportsAttribute(bytes4)` 0xdc680a0f
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors =
            hex"ff7bd03db3602f8d5e280f1194f79a5373ad83348c0b3902193dc20967ebb6b213137d657d25a05e58d14c045d6e12a224ac554dcdfe7f5cdc680a0f";
    }
}
