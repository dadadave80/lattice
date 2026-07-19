// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IWormholeGatewayAdapter} from "@lattice/interfaces/crosschain/IWormholeGatewayAdapter.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {IERC7786Attributes} from "@lattice/interfaces/external/ercs/IERC7786Attributes.sol";
import {IWormholeReceiver, IWormholeRelayer} from "@lattice/interfaces/external/wormhole/IWormholeRelayer.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.WormholeGatewayAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant WORMHOLE_GATEWAY_ADAPTER_STORAGE_SLOT =
    0x46329d8c82c4b2643a1707018dd8f47f4e747c04259ec1eec95a00ddfb1bd600;

/// @dev ERC-165 map slot for `IERC7786GatewaySource` (`0x11967553`). SHARED by all gateway adapters —
///      `keccak256(abi.encode(bytes4(0x11967553), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC7786GATEWAYSOURCE_SLOT =
    0x3c75b8ea75c097979221eb9302e2f0f6009b4ffe0a7198db5dc29979e09ea0e3;

/// @notice A message awaiting a relay request (no-attribute send path).
struct PendingMessage {
    address sender;
    uint256 value;
    bytes recipient;
    bytes payload;
}

/// @notice ERC-7201 namespaced storage for the Wormhole gateway adapter.
/// @custom:storage-location erc7201:lattice.storage.WormholeGatewayAdapter
struct WormholeGatewayAdapterStorage {
    /// @notice The Wormhole relayer (OZ uses an immutable; a Diamond must use storage). APPEND-ONLY.
    address _relayer;
    /// @notice This chain's Wormhole chain id. APPEND-ONLY.
    uint16 _wormholeChainId;
    /// @notice Monotonic message-id counter (source). APPEND-ONLY.
    uint256 _lastMsgId;
    /// @notice Trusted remote gateway adapter per EVM chainId. APPEND-ONLY.
    mapping(uint256 chainId => address remote) _remoteGateways;
    /// @notice EVM chainId => Wormhole chain id (0 = unset). APPEND-ONLY.
    mapping(uint256 chainId => uint16 wormhole) _chainIdToWormhole;
    /// @notice Wormhole chain id => EVM chainId (0 = unset). APPEND-ONLY.
    mapping(uint16 wormhole => uint256 chainId) _wormholeToChainId;
    /// @notice Pending messages by sendId (no-attribute path). APPEND-ONLY.
    mapping(bytes32 sendId => PendingMessage) _pending;
    /// @notice Replay guard: per source chainId, the set of consumed sendIds. APPEND-ONLY.
    mapping(uint256 chainId => mapping(uint256 sendId => bool used)) _executed;
}

/// @title WormholeGatewayAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin community-contracts `WormholeGatewayAdapter` (https://github.com/OpenZeppelin/openzeppelin-community-contracts, commit f7e5f08).
/// @notice Dual-mode ERC-7786 gateway over the Wormhole relayer. Two-phase send (pending → `requestRelay`,
///         or immediate via a `requestRelay` attribute); inbound `receiveWormholeMessages` validates the
///         relayer + trusted source gateway, de-duplicates per (chainId, sendId), and delivers. EVM only.
library WormholeGatewayAdapterLib {
    function wormholeGatewayAdapterStorage() internal pure returns (WormholeGatewayAdapterStorage storage $) {
        assembly {
            $.slot := WORMHOLE_GATEWAY_ADAPTER_STORAGE_SLOT
        }
    }

    /// @notice Configures the relayer + this chain's Wormhole id and registers the gateway-source ERC-165 id.
    function __WormholeGatewayAdapter_init(address relayer_, uint16 wormholeChainId_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        WormholeGatewayAdapterStorage storage $ = wormholeGatewayAdapterStorage();
        $._relayer = relayer_;
        $._wormholeChainId = wormholeChainId_;
        registerInterface();
    }

    /// @notice Writes `true` to the SHARED IERC7786GatewaySource ERC-165 map slot (0x11967553 → ...).
    ///         Same slot the Axelar/OpenBridge adapters register; a Diamond mounts at most one gateway.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC7786GATEWAYSOURCE_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function relayer() internal view returns (address) {
        return wormholeGatewayAdapterStorage()._relayer;
    }

    function wormholeChainId() internal view returns (uint16) {
        return wormholeGatewayAdapterStorage()._wormholeChainId;
    }

    function getWormholeChain(uint256 chainId) internal view returns (uint16) {
        return wormholeGatewayAdapterStorage()._chainIdToWormhole[chainId];
    }

    function getChainId(uint16 wormhole) internal view returns (uint256) {
        return wormholeGatewayAdapterStorage()._wormholeToChainId[wormhole];
    }

    function getRemoteGateway(uint256 chainId) internal view returns (address) {
        return wormholeGatewayAdapterStorage()._remoteGateways[chainId];
    }

    function supportsAttribute(bytes4 selector) internal pure returns (bool) {
        return selector == IERC7786Attributes.requestRelay.selector;
    }

    function quoteRelay(bytes calldata recipient, uint256 gasLimit) internal view returns (uint256 price) {
        (uint256 chainId,) = InteroperableAddress.parseEvmV1(recipient);
        WormholeGatewayAdapterStorage storage $ = wormholeGatewayAdapterStorage();
        (price,) = IWormholeRelayer($._relayer).quoteEVMDeliveryPrice($._chainIdToWormhole[chainId], 0, gasLimit);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    function registerChainEquivalence(uint256 chainId, uint16 wormhole) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        WormholeGatewayAdapterStorage storage $ = wormholeGatewayAdapterStorage();
        if ($._chainIdToWormhole[chainId] != 0 || $._wormholeToChainId[wormhole] != 0) {
            revert IWormholeGatewayAdapter.ChainEquivalenceAlreadyRegistered(chainId);
        }
        $._chainIdToWormhole[chainId] = wormhole;
        $._wormholeToChainId[wormhole] = chainId;
        emit IWormholeGatewayAdapter.RegisteredChainEquivalence(chainId, wormhole);
    }

    function registerRemoteGateway(uint256 chainId, address remote) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        WormholeGatewayAdapterStorage storage $ = wormholeGatewayAdapterStorage();
        if ($._remoteGateways[chainId] != address(0)) {
            revert IWormholeGatewayAdapter.RemoteGatewayAlreadyRegistered(chainId);
        }
        $._remoteGateways[chainId] = remote;
        emit IWormholeGatewayAdapter.RegisteredRemoteGateway(chainId, remote);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   SEND
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Relay parameters (passed as a memory struct to keep callers under the stack limit).
    struct Relay {
        bytes32 id;
        address sender;
        uint256 receiverValue;
        uint256 gasLimit;
        address refundRecipient;
        uint256 totalValue;
        bytes recipient;
        bytes payload;
    }

    /// @notice ERC-7786 source. No attribute → store pending (return non-zero sendId); one `requestRelay`
    ///         attribute → dispatch immediately (return 0); more → revert.
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        internal
        returns (bytes32)
    {
        bytes32 sendId = bytes32(++wormholeGatewayAdapterStorage()._lastMsgId);
        if (attributes.length == 0) return _sendPending(sendId, recipient, payload);
        if (attributes.length == 1) {
            _sendImmediate(sendId, recipient, payload, attributes);
            return bytes32(0);
        }
        revert IWormholeGatewayAdapter.DuplicatedAttribute();
    }

    /// @dev No-attribute path: hold the message (and any value) until {requestRelay}. Split out for stack.
    function _sendPending(bytes32 sendId, bytes calldata recipient, bytes calldata payload) private returns (bytes32) {
        wormholeGatewayAdapterStorage()._pending[sendId] = PendingMessage(msg.sender, msg.value, recipient, payload);
        emit IERC7786GatewaySource.MessageSent(
            sendId,
            InteroperableAddress.formatEvmV1(block.chainid, msg.sender),
            recipient,
            payload,
            msg.value,
            new bytes[](0)
        );
        return sendId;
    }

    /// @dev Single-`requestRelay`-attribute path: dispatch immediately. Split out for stack.
    function _sendImmediate(
        bytes32 sendId,
        bytes calldata recipient,
        bytes calldata payload,
        bytes[] calldata attributes
    ) private {
        (bool ok, uint256 value, uint256 gasLimit, address refund) = _decodeRequestRelay(attributes[0]);
        if (!ok) revert IERC7786GatewaySource.UnsupportedAttribute(bytes4(attributes[0]));
        emit IERC7786GatewaySource.MessageSent(
            bytes32(0),
            InteroperableAddress.formatEvmV1(block.chainid, msg.sender),
            recipient,
            payload,
            msg.value,
            attributes
        );
        _relay(Relay(sendId, msg.sender, value, gasLimit, refund, msg.value, recipient, payload));
    }

    /// @notice Dispatches a previously-stored pending message via the Wormhole relayer.
    function requestRelay(bytes32 sendId, uint256 gasLimit, address refundRecipient) internal {
        WormholeGatewayAdapterStorage storage $ = wormholeGatewayAdapterStorage();
        PendingMessage memory m = $._pending[sendId];
        if (m.sender == address(0)) revert IWormholeGatewayAdapter.UnknownMessage(sendId);
        delete $._pending[sendId];
        _relay(Relay(sendId, m.sender, m.value, gasLimit, refundRecipient, m.value + msg.value, m.recipient, m.payload));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  RECEIVE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Wormhole delivery callback: validate relayer + source gateway, de-dup, deliver.
    function receiveWormholeMessages(
        bytes calldata payload,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) internal {
        WormholeGatewayAdapterStorage storage $ = wormholeGatewayAdapterStorage();
        if (msg.sender != $._relayer) revert IWormholeGatewayAdapter.NotWormholeRelayer(msg.sender);

        uint256 chainId = $._wormholeToChainId[sourceChain];
        if (bytes32(uint256(uint160($._remoteGateways[chainId]))) != sourceAddress) {
            revert IWormholeGatewayAdapter.InvalidOriginGateway(sourceChain, sourceAddress);
        }

        (bytes32 sendId, bytes memory sender, bytes memory recipient, bytes memory inner) =
            abi.decode(payload, (bytes32, bytes, bytes, bytes));

        if ($._executed[chainId][uint256(sendId)]) {
            revert IWormholeGatewayAdapter.MessageAlreadyExecuted(chainId, uint256(sendId));
        }
        $._executed[chainId][uint256(sendId)] = true;

        (, address target) = InteroperableAddress.parseEvmV1(recipient);
        if (
            IERC7786Recipient(target).receiveMessage{value: msg.value}(deliveryHash, sender, inner)
                != IERC7786Recipient.receiveMessage.selector
        ) {
            revert IWormholeGatewayAdapter.RecipientExecutionFailed();
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Encodes the wire payload and dispatches to the trusted remote gateway via the relayer.
    function _relay(Relay memory p) private {
        (uint256 chainId,) = InteroperableAddress.parseEvmV1(p.recipient);
        WormholeGatewayAdapterStorage storage $ = wormholeGatewayAdapterStorage();
        IWormholeRelayer($._relayer).sendPayloadToEvm{value: p.totalValue}(
            $._chainIdToWormhole[chainId],
            $._remoteGateways[chainId],
            abi.encode(p.id, InteroperableAddress.formatEvmV1(block.chainid, p.sender), p.recipient, p.payload),
            p.receiverValue,
            p.gasLimit,
            $._wormholeChainId,
            p.refundRecipient
        );
    }

    /// @notice Decodes a `requestRelay` attribute. Returns `ok=false` if the selector/length doesn't match.
    function _decodeRequestRelay(bytes calldata attr)
        private
        pure
        returns (bool ok, uint256 value, uint256 gasLimit, address refundRecipient)
    {
        if (attr.length < 0x64 || bytes4(attr[0:4]) != IERC7786Attributes.requestRelay.selector) {
            return (false, 0, 0, address(0));
        }
        (value, gasLimit, refundRecipient) = abi.decode(attr[4:], (uint256, uint256, address));
        ok = true;
    }
}
