// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ILayerZeroGatewayAdapter} from "@lattice/interfaces/crosschain/ILayerZeroGatewayAdapter.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/IERC7786.sol";
import {
    ILayerZeroEndpointV2,
    MessagingFee,
    MessagingParams,
    MessagingReceipt,
    Origin
} from "@lattice/interfaces/external/ILayerZeroEndpointV2.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.LayerZeroGatewayAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant LAYERZERO_GATEWAY_ADAPTER_STORAGE_SLOT =
    0xbca2daa6d08cb277e523bf7dcd928e312ddbb7f9ac88be435916dda92924d100;

/// @dev ERC-165 map slot for `IERC7786GatewaySource` (`0x11967553`). SHARED by all gateway adapters —
///      `keccak256(abi.encode(bytes4(0x11967553), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC7786GATEWAYSOURCE_SLOT =
    0x3c75b8ea75c097979221eb9302e2f0f6009b4ffe0a7198db5dc29979e09ea0e3;

/// @notice Per-destination executor config: the `lzReceive` gas and the native msg.value delivered to the peer,
///         synthesized into a LayerZero Type-3 options blob at send time. Packs into a single slot.
struct DestinationConfig {
    uint128 gas;
    uint128 msgValue;
}

/// @notice ERC-7201 namespaced storage for the LayerZero gateway adapter.
/// @custom:storage-location erc7201:lattice.storage.LayerZeroGatewayAdapter
struct LayerZeroGatewayAdapterStorage {
    /// @notice The LayerZero v2 EndpointV2 (OZ-style immutable → Diamond storage). APPEND-ONLY.
    address _endpoint;
    /// @notice EVM chainId => LayerZero eid (0 = unset). APPEND-ONLY.
    mapping(uint256 chainId => uint32 eid) _chainIdToEid;
    /// @notice LayerZero eid => EVM chainId (0 = unset). APPEND-ONLY.
    mapping(uint32 eid => uint256 chainId) _eidToChainId;
    /// @notice Trusted 32-byte remote peer (adapter) per EVM chainId (0 = unset). APPEND-ONLY.
    mapping(uint256 chainId => bytes32 peer) _peers;
    /// @notice Per-destination executor gas + native msg.value (gas 0 = unconfigured). APPEND-ONLY.
    mapping(uint256 chainId => DestinationConfig) _destConfig;
    /// @notice Replay guard: per source chainId, the set of consumed LayerZero guids. APPEND-ONLY.
    mapping(uint256 chainId => mapping(bytes32 guid => bool used)) _executed;
}

/// @title LayerZeroGatewayAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from LayerZero v2 (https://github.com/LayerZero-Labs/LayerZero-v2)
/// @notice Logic + ERC-7201 storage for the LayerZero v2 ERC-7786 gateway adapter. `sendMessage` builds a
///         LayerZero `MessagingParams`, quotes the native fee via `endpoint.quote`, and dispatches via
///         `endpoint.send` (native fee only, excess refunded); `lzReceive` is the endpoint-gated delivery
///         callback that validates the source eid + trusted peer, de-duplicates per (chainId, guid), and
///         delivers to the ERC-7930 recipient. EVM chains only. LayerZero routes by `uint32` eid, not chainId.
/// @dev The adapter is its own OApp. Wire message = `abi.encode(senderInteropAddr, recipientInteropAddr,
///      innerPayload)`; the LayerZero `receiver` field targets the trusted 32-byte peer, which forwards to the
///      final recipient. `options` is a Type-3 executor `lzReceive` blob synthesized INLINE from the admin
///      per-dest gas + msg.value (no OptionsBuilder dependency).
library LayerZeroGatewayAdapterLib {
    /// @dev LayerZero Type-3 options container prefix.
    uint16 private constant OPTIONS_TYPE_3 = 3;
    /// @dev Executor worker id inside a Type-3 options blob.
    uint8 private constant EXECUTOR_WORKER_ID = 1;
    /// @dev Executor option type for the destination `lzReceive` call.
    uint8 private constant OPTION_TYPE_LZRECEIVE = 1;

    function layerZeroGatewayAdapterStorage() internal pure returns (LayerZeroGatewayAdapterStorage storage $) {
        assembly {
            $.slot := LAYERZERO_GATEWAY_ADAPTER_STORAGE_SLOT
        }
    }

    /// @notice Stores the endpoint and registers the gateway-source ERC-165 id. The adapter is its own OApp;
    ///         `setDelegate` is NOT called at init (only needed to reconfigure LayerZero libs later).
    function __LayerZeroGatewayAdapter_init(address endpoint_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        layerZeroGatewayAdapterStorage()._endpoint = endpoint_;
        registerInterface();
    }

    /// @notice Writes `true` to the SHARED IERC7786GatewaySource ERC-165 map slot (0x11967553 → ...).
    ///         Same slot the CCIP/Wormhole/Axelar adapters register; a Diamond mounts at most one gateway.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC7786GATEWAYSOURCE_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function endpoint() internal view returns (address) {
        return layerZeroGatewayAdapterStorage()._endpoint;
    }

    function getEid(uint256 chainId) internal view returns (uint32) {
        return layerZeroGatewayAdapterStorage()._chainIdToEid[chainId];
    }

    function getChainId(uint32 eid) internal view returns (uint256) {
        return layerZeroGatewayAdapterStorage()._eidToChainId[eid];
    }

    function getPeer(uint256 chainId) internal view returns (bytes32) {
        return layerZeroGatewayAdapterStorage()._peers[chainId];
    }

    function getDestinationGas(uint256 chainId) internal view returns (uint128) {
        return layerZeroGatewayAdapterStorage()._destConfig[chainId].gas;
    }

    function getDestinationMsgValue(uint256 chainId) internal view returns (uint128) {
        return layerZeroGatewayAdapterStorage()._destConfig[chainId].msgValue;
    }

    /// @notice No `sendMessage` attributes are supported by this adapter (per-dest gas is admin-configured).
    function supportsAttribute(bytes4) internal pure returns (bool) {
        return false;
    }

    /// @notice Quotes the LayerZero native fee to send `payload` to `recipient` (ERC-7930).
    function quoteFee(bytes calldata recipient, bytes calldata payload) internal view returns (uint256) {
        MessagingParams memory params = _buildParams(recipient, payload);
        return ILayerZeroEndpointV2(layerZeroGatewayAdapterStorage()._endpoint).quote(params, address(this)).nativeFee;
    }

    /// @notice LayerZero receiver policy: whether the OApp accepts a new path from `_origin` (peer must match).
    function allowInitializePath(Origin calldata origin) internal view returns (bool) {
        LayerZeroGatewayAdapterStorage storage $ = layerZeroGatewayAdapterStorage();
        return $._peers[$._eidToChainId[origin.srcEid]] == origin.sender;
    }

    /// @notice LayerZero receiver policy: unordered delivery, so no nonce is enforced (always 0).
    function nextNonce(uint32, bytes32) internal pure returns (uint64) {
        return 0;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    function registerEid(uint256 chainId, uint32 eid) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        LayerZeroGatewayAdapterStorage storage $ = layerZeroGatewayAdapterStorage();
        if ($._chainIdToEid[chainId] != 0 || $._eidToChainId[eid] != 0) {
            revert ILayerZeroGatewayAdapter.EidAlreadyRegistered(chainId);
        }
        $._chainIdToEid[chainId] = eid;
        $._eidToChainId[eid] = chainId;
        emit ILayerZeroGatewayAdapter.RegisteredEid(chainId, eid);
    }

    function registerPeer(uint256 chainId, bytes32 peer) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        LayerZeroGatewayAdapterStorage storage $ = layerZeroGatewayAdapterStorage();
        if ($._peers[chainId] != bytes32(0)) {
            revert ILayerZeroGatewayAdapter.PeerAlreadyRegistered(chainId);
        }
        $._peers[chainId] = peer;
        emit ILayerZeroGatewayAdapter.RegisteredPeer(chainId, peer);
    }

    function configureDestination(uint256 chainId, uint128 gas, uint128 msgValue) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        layerZeroGatewayAdapterStorage()._destConfig[chainId] = DestinationConfig({gas: gas, msgValue: msgValue});
        emit ILayerZeroGatewayAdapter.ConfiguredDestination(chainId, gas, msgValue);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   SEND
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice ERC-7786 source. Quotes the LayerZero native fee and dispatches the message immediately via the
    ///         endpoint. The fee is paid by `msg.sender` via `msg.value` (excess refunded); LayerZero refunds
    ///         any protocol-side native surplus to `msg.sender` too. Diamond funds are never spent.
    /// @dev No attributes are supported — any attribute reverts {UnsupportedAttribute}. Returns the LayerZero
    ///      `guid` as the ERC-7786 `sendId`.
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        internal
        returns (bytes32)
    {
        if (attributes.length != 0) revert IERC7786GatewaySource.UnsupportedAttribute(bytes4(attributes[0]));

        MessagingParams memory params = _buildParams(recipient, payload);
        address endpoint_ = layerZeroGatewayAdapterStorage()._endpoint;
        uint256 nativeFee = ILayerZeroEndpointV2(endpoint_).quote(params, address(this)).nativeFee;
        if (msg.value < nativeFee) revert ILayerZeroGatewayAdapter.InsufficientFee(msg.value, nativeFee);

        MessagingReceipt memory receipt = ILayerZeroEndpointV2(endpoint_).send{value: nativeFee}(params, msg.sender);

        // Refund any native not consumed by the fee back to the sender.
        if (msg.value > nativeFee) {
            (bool ok,) = msg.sender.call{value: msg.value - nativeFee}("");
            if (!ok) revert ILayerZeroGatewayAdapter.RefundFailed();
        }

        emit IERC7786GatewaySource.MessageSent(
            receipt.guid,
            InteroperableAddress.formatEvmV1(block.chainid, msg.sender),
            recipient,
            payload,
            msg.value,
            attributes
        );
        return receipt.guid;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  RECEIVE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice LayerZero delivery callback: DUAL AUTH — `msg.sender` must be the endpoint AND `origin.sender`
    ///         must equal the trusted peer registered for the source eid's chain. De-dups per (chainId, guid),
    ///         marking the guid executed BEFORE the external delivery (checks-effects-interactions), then
    ///         delivers to the ERC-7930 recipient encoded in the message.
    function lzReceive(Origin calldata origin, bytes32 guid, bytes calldata message) internal {
        LayerZeroGatewayAdapterStorage storage $ = layerZeroGatewayAdapterStorage();
        if (msg.sender != $._endpoint) revert ILayerZeroGatewayAdapter.NotEndpoint(msg.sender);

        uint256 chainId = $._eidToChainId[origin.srcEid];
        bytes32 peer = $._peers[chainId];
        // Reject an unregistered source (chainId 0) or an unconfigured peer (bytes32(0)) explicitly, so an
        // eid registered before its peer can never satisfy auth against a zero-sender delivery.
        if (chainId == 0 || peer == bytes32(0) || peer != origin.sender) {
            revert ILayerZeroGatewayAdapter.InvalidOriginGateway(origin.srcEid, origin.sender);
        }

        if ($._executed[chainId][guid]) revert ILayerZeroGatewayAdapter.MessageAlreadyExecuted(chainId, guid);
        $._executed[chainId][guid] = true;

        (bytes memory sender, bytes memory recipient, bytes memory inner) = abi.decode(message, (bytes, bytes, bytes));

        // lzReceive is payable (the executor may forward the admin-configured msg.value); forward it to the
        // recipient so the delivered native value is never trapped in the Diamond.
        (uint256 recipientChainId, address target) = InteroperableAddress.parseEvmV1(recipient);
        // Defense-in-depth: the source routes by the recipient's chainId, so a well-behaved peer only ever
        // delivers messages whose recipient targets THIS chain; a rogue/buggy trusted peer cannot misdirect.
        if (recipientChainId != block.chainid) {
            revert ILayerZeroGatewayAdapter.WrongDestinationChain(recipientChainId);
        }
        if (
            IERC7786Recipient(target).receiveMessage{value: msg.value}(guid, sender, inner)
                != IERC7786Recipient.receiveMessage.selector
        ) {
            revert ILayerZeroGatewayAdapter.RecipientExecutionFailed();
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Builds the LayerZero `MessagingParams` for `recipient`/`payload`.
    /// @dev Reverts {UnknownDestinationChain} if the eid/peer is unset, {DestinationNotConfigured} if the
    ///      executor gas is unset. Wraps the final ERC-7930 recipient inside the wire message and synthesizes
    ///      the Type-3 options from the admin per-dest gas + msg.value.
    function _buildParams(bytes calldata recipient, bytes calldata payload)
        private
        view
        returns (MessagingParams memory params)
    {
        (uint256 chainId,) = InteroperableAddress.parseEvmV1(recipient);
        LayerZeroGatewayAdapterStorage storage $ = layerZeroGatewayAdapterStorage();
        uint32 eid = $._chainIdToEid[chainId];
        bytes32 peer = $._peers[chainId];
        if (eid == 0 || peer == bytes32(0)) revert ILayerZeroGatewayAdapter.UnknownDestinationChain(chainId);
        DestinationConfig memory cfg = $._destConfig[chainId];
        if (cfg.gas == 0) revert ILayerZeroGatewayAdapter.DestinationNotConfigured(chainId);

        params = MessagingParams({
            dstEid: eid,
            receiver: peer,
            message: abi.encode(InteroperableAddress.formatEvmV1(block.chainid, msg.sender), recipient, payload),
            options: _buildOptions(cfg.gas, cfg.msgValue),
            payInLzToken: false
        });
    }

    /// @notice Synthesizes a LayerZero Type-3 options blob carrying a single executor `lzReceive` option with
    ///         `gas` (and `value` when non-zero). Built inline to avoid an OptionsBuilder dependency.
    /// @dev Layout: `type(uint16) || workerId(uint8) || optionLen(uint16) || optionType(uint8) || gas(uint128)
    ///      [|| value(uint128)]`. `optionLen` counts `optionType` (1) + the option data (16, or 32 with value).
    function _buildOptions(uint128 gas, uint128 value) private pure returns (bytes memory) {
        if (value == 0) {
            return abi.encodePacked(OPTIONS_TYPE_3, EXECUTOR_WORKER_ID, uint16(17), OPTION_TYPE_LZRECEIVE, gas);
        }
        return abi.encodePacked(OPTIONS_TYPE_3, EXECUTOR_WORKER_ID, uint16(33), OPTION_TYPE_LZRECEIVE, gas, value);
    }
}
