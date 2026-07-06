// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ZetaChainGatewayAdapterLib} from "@lattice/crosschain/libraries/ZetaChainGatewayAdapterLib.sol";
import {IZetaChainGatewayAdapter} from "@lattice/interfaces/crosschain/IZetaChainGatewayAdapter.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/IERC7786.sol";
import {Callable, MessageContext} from "@lattice/interfaces/external/IGatewayEVM.sol";

/// @title ZetaChainGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ZetaChain (https://github.com/zeta-chain/protocol-contracts)
/// @notice ERC-7786 cross-chain gateway facet over ZetaChain's `GatewayEVM`. `sendMessage` dispatches a message
///         via the gateway to the destination's ZEVM universal app (the hub); `onCall` is the gateway's inbound
///         delivery hook. EVM chains only. HUB-ROUTED — messages flow through a ZetaChain ZEVM universal app, not
///         a direct peer.
/// @dev Stateless delegator — logic/storage live in {ZetaChainGatewayAdapterLib}. The `GatewayEVM` is a DEPLOYED
///      contract (address varies per connected chain), stored at init and mutable by an admin setter. The
///      trusted-remote registry is a forward (`chainId ⇒ app`) + reverse (`app ⇒ chainId`) map of ZEVM universal
///      apps; the gateway-gated `onCall` is the inbound analogue of CCIP's `ccipReceive` / LayerZero's `lzReceive`.
///      Implements {Callable} (`onCall`) so the ZetaChain `GatewayEVM` can deliver inbound messages.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source ZetaChain
contract ZetaChainGatewayAdapter is IERC7786GatewaySource, Callable, IZetaChainGatewayAdapter {
    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        external
        payable
        virtual
        returns (bytes32)
    {
        return ZetaChainGatewayAdapterLib.sendMessage(recipient, payload, attributes);
    }

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 selector) external pure virtual returns (bool) {
        return ZetaChainGatewayAdapterLib.supportsAttribute(selector);
    }

    /// @inheritdoc Callable
    function onCall(MessageContext calldata context, bytes calldata message)
        external
        payable
        virtual
        returns (bytes memory)
    {
        return ZetaChainGatewayAdapterLib.onCall(context, message);
    }

    /// @inheritdoc IZetaChainGatewayAdapter
    function gateway() external view virtual returns (address) {
        return ZetaChainGatewayAdapterLib.gateway();
    }

    /// @inheritdoc IZetaChainGatewayAdapter
    function getRemoteApp(uint256 chainId) external view virtual returns (address) {
        return ZetaChainGatewayAdapterLib.getRemoteApp(chainId);
    }

    /// @inheritdoc IZetaChainGatewayAdapter
    function getChainIdForApp(address remoteApp) external view virtual returns (uint256) {
        return ZetaChainGatewayAdapterLib.getChainIdForApp(remoteApp);
    }

    /// @inheritdoc IZetaChainGatewayAdapter
    function defaultOnRevertGasLimit() external view virtual returns (uint256) {
        return ZetaChainGatewayAdapterLib.defaultOnRevertGasLimit();
    }

    /// @inheritdoc IZetaChainGatewayAdapter
    function setGateway(address gateway_) external virtual {
        ZetaChainGatewayAdapterLib.setGateway(gateway_);
    }

    /// @inheritdoc IZetaChainGatewayAdapter
    function registerRemote(uint256 chainId, address remoteApp) external virtual {
        ZetaChainGatewayAdapterLib.registerRemote(chainId, remoteApp);
    }

    /// @inheritdoc IZetaChainGatewayAdapter
    function setDefaultOnRevertGasLimit(uint256 onRevertGasLimit) external virtual {
        ZetaChainGatewayAdapterLib.setDefaultOnRevertGasLimit(onRevertGasLimit);
    }
}
