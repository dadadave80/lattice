// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HyperbridgeGatewayAdapterLib} from "@lattice/crosschain/libraries/HyperbridgeGatewayAdapterLib.sol";
import {IHyperbridgeGatewayAdapter} from "@lattice/interfaces/crosschain/IHyperbridgeGatewayAdapter.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/IERC7786.sol";
import {IncomingPostRequest, PostRequest} from "@lattice/interfaces/external/IIsmpDispatcher.sol";
import {
    GetRequest,
    IIsmpModule,
    IncomingGetResponse,
    IncomingPostResponse,
    PostResponse
} from "@lattice/interfaces/external/IIsmpModule.sol";

/// @title HyperbridgeGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Hyperbridge (https://github.com/polytope-labs/ismp-solidity)
/// @notice ERC-7786 cross-chain gateway facet over Hyperbridge's ISMP (proof-verified interop: consensus +
///         state proofs aggregated on a Polkadot-secured coprocessor, delivered by permissionless
///         proof-carrying relayers — NO attestation committee). `sendMessage` dispatches a POST request via
///         the IsmpHost, paying the per-byte protocol fee + optional relayer fee in the host's ERC-20
///         `feeToken()` (never `msg.value`); the host-invoked `IIsmpModule` hooks are the inbound surface.
/// @dev Stateless delegator — logic/storage live in {HyperbridgeGatewayAdapterLib}. Implements ALL SIX
///      {IIsmpModule} hooks so the host can notify the module: `onAccept` (delivery) and
///      `onPostRequestTimeout` (native timeout/refund notification — the fee refund itself is host-side to
///      `DispatchPost.payer`, the sending user) are live; the four response/GET hooks revert
///      {HyperbridgeUnsupportedHook} (the adapter dispatches neither GETs nor responses — silently accepting
///      them would be a spoofable no-op surface). EVM recipients only in v1; non-EVM (POLKADOT-/SUBSTRATE-)
///      state machines can be registered raw for inbound auth.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Hyperbridge
contract HyperbridgeGatewayAdapter is IERC7786GatewaySource, IIsmpModule, IHyperbridgeGatewayAdapter {
    /// @inheritdoc IERC7786GatewaySource
    /// @dev `payable` is forced by the interface; the native-token fee path is DEFERRED — stray value reverts.
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        external
        payable
        virtual
        returns (bytes32)
    {
        return HyperbridgeGatewayAdapterLib.sendMessage(recipient, payload, attributes);
    }

    /// @inheritdoc IHyperbridgeGatewayAdapter
    function sendMessageWithFee(bytes calldata recipient, bytes calldata payload, uint256 relayerFee)
        external
        virtual
        returns (bytes32)
    {
        return HyperbridgeGatewayAdapterLib.sendMessageWithFee(recipient, payload, relayerFee);
    }

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 selector) external pure virtual returns (bool) {
        return HyperbridgeGatewayAdapterLib.supportsAttribute(selector);
    }

    /// @inheritdoc IIsmpModule
    function onAccept(IncomingPostRequest calldata incoming) external virtual {
        HyperbridgeGatewayAdapterLib.onAccept(incoming);
    }

    /// @inheritdoc IIsmpModule
    function onPostRequestTimeout(PostRequest calldata request) external virtual {
        HyperbridgeGatewayAdapterLib.onPostRequestTimeout(request);
    }

    /// @inheritdoc IIsmpModule
    /// @dev Never used — the adapter dispatches no requests that expect responses.
    function onPostResponse(IncomingPostResponse calldata) external virtual {
        HyperbridgeGatewayAdapterLib.unsupportedHook();
    }

    /// @inheritdoc IIsmpModule
    /// @dev Never used — the adapter dispatches no GET requests.
    function onGetResponse(IncomingGetResponse calldata) external virtual {
        HyperbridgeGatewayAdapterLib.unsupportedHook();
    }

    /// @inheritdoc IIsmpModule
    /// @dev Never used — the adapter dispatches no responses that could time out.
    function onPostResponseTimeout(PostResponse calldata) external virtual {
        HyperbridgeGatewayAdapterLib.unsupportedHook();
    }

    /// @inheritdoc IIsmpModule
    /// @dev Never used — the adapter dispatches no GET requests that could time out.
    function onGetTimeout(GetRequest calldata) external virtual {
        HyperbridgeGatewayAdapterLib.unsupportedHook();
    }

    /// @inheritdoc IHyperbridgeGatewayAdapter
    function ismpHost() external view virtual returns (address) {
        return HyperbridgeGatewayAdapterLib.ismpHost();
    }

    /// @inheritdoc IHyperbridgeGatewayAdapter
    function hyperbridgeFeeToken() external view virtual returns (address) {
        return HyperbridgeGatewayAdapterLib.hyperbridgeFeeToken();
    }

    /// @inheritdoc IHyperbridgeGatewayAdapter
    function stateMachineIdOf(uint256 chainId) external view virtual returns (bytes memory) {
        return HyperbridgeGatewayAdapterLib.stateMachineIdOf(chainId);
    }

    /// @inheritdoc IHyperbridgeGatewayAdapter
    function chainIdOfStateMachine(bytes calldata stateMachineId) external view virtual returns (uint256) {
        return HyperbridgeGatewayAdapterLib.chainIdOfStateMachine(stateMachineId);
    }

    /// @inheritdoc IHyperbridgeGatewayAdapter
    function hyperbridgeRemoteModuleOf(uint256 chainId) external view virtual returns (bytes memory) {
        return HyperbridgeGatewayAdapterLib.hyperbridgeRemoteModuleOf(chainId);
    }

    /// @inheritdoc IHyperbridgeGatewayAdapter
    function hyperbridgeDestTimeoutOf(uint256 chainId) external view virtual returns (uint64) {
        return HyperbridgeGatewayAdapterLib.hyperbridgeDestTimeoutOf(chainId);
    }

    /// @inheritdoc IHyperbridgeGatewayAdapter
    function quoteDispatchFee(bytes calldata recipient, bytes calldata payload, uint256 relayerFee)
        external
        view
        virtual
        returns (uint256)
    {
        return HyperbridgeGatewayAdapterLib.quoteDispatchFee(recipient, payload, relayerFee);
    }

    /// @inheritdoc IHyperbridgeGatewayAdapter
    function registerStateMachine(uint256 chainId) external virtual {
        HyperbridgeGatewayAdapterLib.registerStateMachine(chainId);
    }

    /// @inheritdoc IHyperbridgeGatewayAdapter
    function registerStateMachineRaw(uint256 chainId, bytes calldata stateMachineId) external virtual {
        HyperbridgeGatewayAdapterLib.registerStateMachineRaw(chainId, stateMachineId);
    }

    /// @inheritdoc IHyperbridgeGatewayAdapter
    function registerRemoteModule(uint256 chainId, bytes calldata module) external virtual {
        HyperbridgeGatewayAdapterLib.registerRemoteModule(chainId, module);
    }

    /// @inheritdoc IHyperbridgeGatewayAdapter
    function configureDestinationTimeout(uint256 chainId, uint64 timeout) external virtual {
        HyperbridgeGatewayAdapterLib.configureDestinationTimeout(chainId, timeout);
    }
}
