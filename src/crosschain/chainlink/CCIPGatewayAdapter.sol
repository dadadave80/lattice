// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CCIPGatewayAdapterLib} from "@lattice/crosschain/chainlink/CCIPGatewayAdapterLib.sol";
import {ICCIPGatewayAdapter} from "@lattice/interfaces/crosschain/ICCIPGatewayAdapter.sol";
import {Client} from "@lattice/interfaces/external/chainlink/CCIPClient.sol";
import {IAny2EVMMessageReceiver} from "@lattice/interfaces/external/chainlink/IAny2EVMMessageReceiver.sol";
import {IAny2EVMMessageReceiverV2} from "@lattice/interfaces/external/chainlink/IAny2EVMMessageReceiverV2.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/ercs/IERC7786.sol";

/// @title CCIPGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Chainlink CCIP (https://github.com/smartcontractkit/chainlink-ccip)
/// @notice ERC-7786 cross-chain gateway facet over Chainlink CCIP. `sendMessage` quotes + submits a CCIP
///         message via the router; `ccipReceive` is the router's delivery callback. EVM chains only.
/// @dev Stateless delegator — logic/storage live in {CCIPGatewayAdapterLib}. CCIP routes by `uint64` chain
///      selector (the lib holds a chainId ⇄ selector map); the router-gated `ccipReceive` is the inbound
///      analogue of Wormhole's `receiveWormholeMessages` / Axelar's `execute`. Implements the V2 CCIP
///      receiver (`IAny2EVMMessageReceiverV2`): V1 `ccipReceive` delivery plus `getCCVsAndFinalityConfig` so
///      CCV-enabled lanes can read the admin-configured Cross-Chain Verifier / finality requirements.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Chainlink
contract CCIPGatewayAdapter is IERC7786GatewaySource, IAny2EVMMessageReceiverV2, ICCIPGatewayAdapter {
    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        external
        payable
        virtual
        returns (bytes32)
    {
        return CCIPGatewayAdapterLib.sendMessage(recipient, payload, attributes);
    }

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 selector) external pure virtual returns (bool) {
        return CCIPGatewayAdapterLib.supportsAttribute(selector);
    }

    /// @inheritdoc IAny2EVMMessageReceiver
    function ccipReceive(Client.Any2EVMMessage calldata message) external virtual {
        CCIPGatewayAdapterLib.ccipReceive(message);
    }

    /// @inheritdoc IAny2EVMMessageReceiverV2
    function getCCVsAndFinalityConfig(uint64 sourceChainSelector, bytes calldata)
        external
        view
        virtual
        returns (
            address[] memory requiredCCVs,
            address[] memory optionalCCVs,
            uint8 optionalThreshold,
            bytes4 allowedFinalityConfig
        )
    {
        return CCIPGatewayAdapterLib.getCCVsAndFinalityConfig(sourceChainSelector);
    }

    /// @inheritdoc ICCIPGatewayAdapter
    function router() external view virtual returns (address) {
        return CCIPGatewayAdapterLib.router();
    }

    /// @inheritdoc ICCIPGatewayAdapter
    function feeToken() external view virtual returns (address) {
        return CCIPGatewayAdapterLib.feeToken();
    }

    /// @inheritdoc ICCIPGatewayAdapter
    function getChainSelector(uint256 chainId) external view virtual returns (uint64) {
        return CCIPGatewayAdapterLib.getChainSelector(chainId);
    }

    /// @inheritdoc ICCIPGatewayAdapter
    function getChainId(uint64 selector) external view virtual returns (uint256) {
        return CCIPGatewayAdapterLib.getChainId(selector);
    }

    /// @inheritdoc ICCIPGatewayAdapter
    function getRemoteGateway(uint256 chainId) external view virtual returns (address) {
        return CCIPGatewayAdapterLib.getRemoteGateway(chainId);
    }

    /// @inheritdoc ICCIPGatewayAdapter
    function getDestinationGasLimit(uint256 chainId) external view virtual returns (uint256) {
        return CCIPGatewayAdapterLib.getDestinationGasLimit(chainId);
    }

    /// @inheritdoc ICCIPGatewayAdapter
    function getAllowOutOfOrderExecution(uint256 chainId) external view virtual returns (bool) {
        return CCIPGatewayAdapterLib.getAllowOutOfOrderExecution(chainId);
    }

    /// @inheritdoc ICCIPGatewayAdapter
    function quoteFee(bytes calldata recipient, bytes calldata payload) external view virtual returns (uint256) {
        return CCIPGatewayAdapterLib.quoteFee(recipient, payload);
    }

    /// @inheritdoc ICCIPGatewayAdapter
    function registerChainSelector(uint256 chainId, uint64 selector) external virtual {
        CCIPGatewayAdapterLib.registerChainSelector(chainId, selector);
    }

    /// @inheritdoc ICCIPGatewayAdapter
    function registerRemoteGateway(uint256 chainId, address remote) external virtual {
        CCIPGatewayAdapterLib.registerRemoteGateway(chainId, remote);
    }

    /// @inheritdoc ICCIPGatewayAdapter
    function configureDestination(uint256 chainId, uint256 gasLimit, bool allowOutOfOrderExecution) external virtual {
        CCIPGatewayAdapterLib.configureDestination(chainId, gasLimit, allowOutOfOrderExecution);
    }

    /// @inheritdoc ICCIPGatewayAdapter
    function setFeeToken(address feeToken_) external virtual {
        CCIPGatewayAdapterLib.setFeeToken(feeToken_);
    }

    /// @inheritdoc ICCIPGatewayAdapter
    function configureCCV(
        uint256 chainId,
        address[] calldata requiredCCVs,
        address[] calldata optionalCCVs,
        uint8 optionalThreshold,
        bytes4 allowedFinalityConfig
    ) external virtual {
        CCIPGatewayAdapterLib.configureCCV(
            chainId, requiredCCVs, optionalCCVs, optionalThreshold, allowedFinalityConfig
        );
    }

    /// @inheritdoc ICCIPGatewayAdapter
    function getCCVConfig(uint256 chainId)
        external
        view
        virtual
        returns (
            address[] memory requiredCCVs,
            address[] memory optionalCCVs,
            uint8 optionalThreshold,
            bytes4 allowedFinalityConfig
        )
    {
        return CCIPGatewayAdapterLib.getCCVConfig(chainId);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect CCIPGatewayAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `ccipReceive((bytes32,uint64,bytes,bytes,(address,uint256)[]))` 0x85572ffb
    ///      `configureCCV(uint256,address[],address[],uint8,bytes4)` 0xbc633c78
    ///      `configureDestination(uint256,uint256,bool)` 0xf8291572
    ///      `feeToken()` 0x647846a5
    ///      `getAllowOutOfOrderExecution(uint256)` 0x578599f7
    ///      `getCCVConfig(uint256)` 0x0a2525d2
    ///      `getCCVsAndFinalityConfig(uint64,bytes)` 0x1bfc84d0
    ///      `getChainId(uint64)` 0x8b6cecf8
    ///      `getChainSelector(uint256)` 0x92e2106f
    ///      `getDestinationGasLimit(uint256)` 0xb168cf09
    ///      `getRemoteGateway(uint256)` 0x752bcf06
    ///      `quoteFee(bytes,bytes)` 0x58d14c04
    ///      `registerChainSelector(uint256,uint64)` 0xef251049
    ///      `registerRemoteGateway(uint256,address)` 0x997ce1f0
    ///      `router()` 0xf887ea40
    ///      `sendMessage(bytes,bytes,bytes[])` 0xcdfe7f5c
    ///      `setFeeToken(address)` 0x15cce224
    ///      `supportsAttribute(bytes4)` 0xdc680a0f
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors =
            hex"85572ffbbc633c78f8291572647846a5578599f70a2525d21bfc84d08b6cecf892e2106fb168cf09752bcf0658d14c04ef251049997ce1f0f887ea40cdfe7f5c15cce224dc680a0f";
    }
}
