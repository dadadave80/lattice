// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CCIPGatewayAdapterLib} from "@lattice/crosschain/libraries/CCIPGatewayAdapterLib.sol";
import {ICCIPGatewayAdapter} from "@lattice/interfaces/ICCIPGatewayAdapter.sol";
import {Client} from "@lattice/interfaces/external/CCIPClient.sol";
import {IAny2EVMMessageReceiver} from "@lattice/interfaces/external/IAny2EVMMessageReceiver.sol";
import {IAny2EVMMessageReceiverV2} from "@lattice/interfaces/external/IAny2EVMMessageReceiverV2.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/IERC7786.sol";

/// @title CCIPGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
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
}
