// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {
    IL2ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice/interfaces/crosschain/IL2ToL2CrossDomainMessengerGatewayAdapter.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {IL2ToL2CrossDomainMessenger} from "@lattice/interfaces/external/optimism/IL2ToL2CrossDomainMessenger.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.L2ToL2CrossDomainMessengerGatewayAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant L2_TO_L2_CROSS_DOMAIN_MESSENGER_GATEWAY_ADAPTER_STORAGE_SLOT =
    0x7d097b8d74c3eca1712de7b01bb2e081ac18f7660e60d35d0a11a670a90beb00;

/// @dev ERC-165 map slot for `IERC7786GatewaySource` (`0x11967553`). SHARED by all gateway adapters —
///      `keccak256(abi.encode(bytes4(0x11967553), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC7786GATEWAYSOURCE_SLOT =
    0x3c75b8ea75c097979221eb9302e2f0f6009b4ffe0a7198db5dc29979e09ea0e3;

/// @dev The OP Superchain `L2ToL2CrossDomainMessenger` predeploy — fixed on every Superchain chain.
///      PRE-MAINNET: re-verify this address (and the message encoding) against the then-current
///      `ethereum-optimism/optimism` `contracts-bedrock` release before ANY production deploy.
address constant L2_TO_L2_CROSS_DOMAIN_MESSENGER = 0x4200000000000000000000000000000000000023;

/// @notice ERC-7201 namespaced storage for the L2ToL2CrossDomainMessenger gateway adapter.
/// @custom:storage-location erc7201:lattice.storage.L2ToL2CrossDomainMessengerGatewayAdapter
struct L2ToL2CrossDomainMessengerGatewayAdapterStorage {
    /// @notice Trusted remote gateway adapter (the sibling adapter) per EVM chainId (0 = unset). APPEND-ONLY.
    mapping(uint256 chainId => address remoteAdapter) _remoteAdapters;
    /// @notice Replay guard: per source chainId, the set of consumed message ids. APPEND-ONLY.
    mapping(uint256 chainId => mapping(bytes32 id => bool used)) _executed;
    /// @notice Monotonic outbound counter. The OP messenger exposes no per-message id to the delivery target, so
    ///         each dispatched message carries this source-minted nonce, giving a globally-unique (source, nonce)
    ///         id on delivery (matching the unique-id semantics of the CCIP/LayerZero/Wormhole siblings).
    uint256 _outboundNonce;
}

/// @title L2ToL2CrossDomainMessengerGatewayAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Optimism (https://github.com/ethereum-optimism/optimism)
/// @notice Logic + ERC-7201 storage for the OP Superchain `L2ToL2CrossDomainMessenger` ERC-7786 gateway adapter.
///         `sendMessage` wraps the ERC-7930 envelope as the calldata the messenger will execute on the sibling
///         adapter and dispatches via `messenger.sendMessage` (no fee — the relayer pays gas at `relayMessage`);
///         `receiveCrossChainMessage` is the messenger-invoked delivery callback that authenticates the source
///         out-of-band via `crossDomainMessageContext`, de-duplicates, and delivers to the ERC-7930 recipient.
///         EVM (Superchain) chains only. Routes by BARE EVM chainId — no eid/selector translation.
/// @dev INVERTED INBOUND AUTH: the adapter's inbound function is the `_target` the messenger CALLs during
///      `relayMessage`, so `msg.sender` is the messenger predeploy (NOT the remote gateway). Trust is therefore
///      established by reading the authenticated `(sender, source)` back from `messenger.crossDomainMessageContext()`
///      and matching `sender` to the registered remote adapter for `source`. The messenger self-dedups on the
///      message hash (`relayMessage` reverts on replay via `successfulMessages`), so the per-envelope guard here
///      is cheap defense-in-depth rather than the primary replay defense. Wire message =
///      `abi.encodeCall(receiveCrossChainMessage, (senderInterop, recipient, payload))`.
library L2ToL2CrossDomainMessengerGatewayAdapterLib {
    function l2ToL2CrossDomainMessengerGatewayAdapterStorage()
        internal
        pure
        returns (L2ToL2CrossDomainMessengerGatewayAdapterStorage storage $)
    {
        assembly {
            $.slot := L2_TO_L2_CROSS_DOMAIN_MESSENGER_GATEWAY_ADAPTER_STORAGE_SLOT
        }
    }

    /// @notice Registers the gateway-source ERC-165 id. The messenger is the fixed predeploy constant, so there
    ///         is no endpoint/router to persist at init.
    function __L2ToL2CrossDomainMessengerGatewayAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the SHARED IERC7786GatewaySource ERC-165 map slot (0x11967553 → ...). Same slot
    ///         the CCIP/LayerZero/Wormhole/Axelar adapters register; a Diamond mounts at most one gateway.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC7786GATEWAYSOURCE_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function messenger() internal pure returns (address) {
        return L2_TO_L2_CROSS_DOMAIN_MESSENGER;
    }

    function getRemoteAdapter(uint256 chainId) internal view returns (address) {
        return l2ToL2CrossDomainMessengerGatewayAdapterStorage()._remoteAdapters[chainId];
    }

    /// @notice No `sendMessage` attributes are supported by this adapter: gas is supplied by the relayer at
    ///         `relayMessage`, so there is no per-destination gas config to attach.
    function supportsAttribute(bytes4) internal pure returns (bool) {
        return false;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    function registerRemoteAdapter(uint256 chainId, address remoteAdapter) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (remoteAdapter == address(0)) revert IL2ToL2CrossDomainMessengerGatewayAdapter.InvalidRemoteAdapter();
        L2ToL2CrossDomainMessengerGatewayAdapterStorage storage $ = l2ToL2CrossDomainMessengerGatewayAdapterStorage();
        if ($._remoteAdapters[chainId] != address(0)) {
            revert IL2ToL2CrossDomainMessengerGatewayAdapter.RemoteAdapterAlreadyRegistered(chainId);
        }
        $._remoteAdapters[chainId] = remoteAdapter;
        emit IL2ToL2CrossDomainMessengerGatewayAdapter.RegisteredRemoteAdapter(chainId, remoteAdapter);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   SEND
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice ERC-7786 source. Wraps the ERC-7930 envelope as the calldata the messenger will execute on the
    ///         destination sibling adapter and dispatches it via `messenger.sendMessage`. Charges NO fee: gas is
    ///         supplied by the relayer at `relayMessage` and the messenger takes no native value, so a non-empty
    ///         `msg.value` is rejected. Returns the messenger's message hash as the ERC-7786 `sendId`.
    /// @dev No attributes are supported — any attribute reverts {UnsupportedAttribute}.
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        internal
        returns (bytes32)
    {
        if (attributes.length != 0) revert IERC7786GatewaySource.UnsupportedAttribute(bytes4(attributes[0]));
        // The messenger charges no native fee (the relayer pays gas at relayMessage); reject stray value so it is
        // never trapped in the Diamond.
        if (msg.value != 0) revert IL2ToL2CrossDomainMessengerGatewayAdapter.UnexpectedValue(msg.value);

        // Envelope carries a source-owned monotonic nonce (`$._outboundNonce++`) so the delivery id is globally
        // unique per (source, nonce) rather than envelope content — otherwise two byte-identical-but-distinct
        // messages would collide on delivery (one permanently dropped) and the recipient would see a non-unique id.
        // Dispatch is block-scoped so the routing locals free before the emit (non-via-IR stack budget).
        bytes32 messageHash;
        {
            (uint256 destChainId,) = InteroperableAddress.parseEvmV1(recipient);
            L2ToL2CrossDomainMessengerGatewayAdapterStorage storage $ =
                l2ToL2CrossDomainMessengerGatewayAdapterStorage();
            address remoteAdapter = $._remoteAdapters[destChainId];
            if (remoteAdapter == address(0)) {
                revert IL2ToL2CrossDomainMessengerGatewayAdapter.UnknownDestinationChain(destChainId);
            }
            bytes memory message = abi.encodeCall(
                IL2ToL2CrossDomainMessengerGatewayAdapter.receiveCrossChainMessage,
                (InteroperableAddress.formatEvmV1(block.chainid, msg.sender), recipient, payload, $._outboundNonce++)
            );
            messageHash = IL2ToL2CrossDomainMessenger(L2_TO_L2_CROSS_DOMAIN_MESSENGER)
                .sendMessage(destChainId, remoteAdapter, message);
        }

        emit IERC7786GatewaySource.MessageSent(
            messageHash,
            InteroperableAddress.formatEvmV1(block.chainid, msg.sender),
            recipient,
            payload,
            msg.value,
            attributes
        );
        return messageHash;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  RECEIVE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Messenger-invoked delivery callback (INVERTED AUTH). Authenticates: (1) `msg.sender` is the
    ///         messenger predeploy; (2) the authenticated cross-domain `(sender, source)` read from
    ///         `crossDomainMessageContext()` matches the registered (non-zero) remote adapter for `source`.
    ///         De-dups per (source, envelope id) marking BEFORE delivery (strict CEI), then delivers to the
    ///         ERC-7930 recipient after asserting it targets THIS chain.
    /// @dev The per-envelope guard is defense-in-depth: the messenger already self-dedups on the message hash,
    ///      reverting `relayMessage` on replay via `successfulMessages`.
    function receiveCrossChainMessage(
        bytes calldata sender,
        bytes calldata recipient,
        bytes calldata payload,
        uint256 nonce
    ) internal {
        if (msg.sender != L2_TO_L2_CROSS_DOMAIN_MESSENGER) {
            revert IL2ToL2CrossDomainMessengerGatewayAdapter.NotMessenger(msg.sender);
        }

        L2ToL2CrossDomainMessengerGatewayAdapterStorage storage $ = l2ToL2CrossDomainMessengerGatewayAdapterStorage();

        // INVERTED AUTH + CEI replay guard, then the globally-unique delivery id. Block-scoped so the auth locals
        // free before delivery (non-via-IR stack budget). The id is derived from the authenticated source + the
        // source-minted nonce (NOT envelope content), so two byte-identical-but-distinct messages get distinct ids
        // (neither dropped) and the recipient sees a unique id. Redundant defense-in-depth over the messenger's
        // own self-dedup; marked BEFORE delivery.
        bytes32 id;
        {
            // Read the authenticated (sender, source) back from the messenger; reject an unregistered source
            // (remoteAdapter 0) explicitly, so a zero-sender delivery can never satisfy auth against an
            // unconfigured chain.
            (address crossSender, uint256 source) =
                IL2ToL2CrossDomainMessenger(L2_TO_L2_CROSS_DOMAIN_MESSENGER).crossDomainMessageContext();
            address remoteAdapter = $._remoteAdapters[source];
            if (remoteAdapter == address(0) || crossSender != remoteAdapter) {
                revert IL2ToL2CrossDomainMessengerGatewayAdapter.InvalidOriginGateway(source, crossSender);
            }
            id = keccak256(abi.encode(source, nonce));
            if ($._executed[source][id]) {
                revert IL2ToL2CrossDomainMessengerGatewayAdapter.MessageAlreadyExecuted(source, id);
            }
            $._executed[source][id] = true;
        }

        // A well-behaved remote adapter only ever routes messages whose recipient targets THIS chain; reject
        // anything else so a rogue/misconfigured remote adapter cannot misdirect delivery. Scoped so only `target`
        // survives to the delivery call.
        address target;
        {
            (uint256 recipientChainId, address target_) = InteroperableAddress.parseEvmV1(recipient);
            if (recipientChainId != block.chainid) {
                revert IL2ToL2CrossDomainMessengerGatewayAdapter.WrongDestinationChain(recipientChainId);
            }
            target = target_;
        }
        if (IERC7786Recipient(target).receiveMessage(id, sender, payload) != IERC7786Recipient.receiveMessage.selector)
        {
            revert IL2ToL2CrossDomainMessengerGatewayAdapter.RecipientExecutionFailed();
        }
    }
}
