// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {
    IL1ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice/interfaces/crosschain/IL1ToL2CrossDomainMessengerGatewayAdapter.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {ICrossDomainMessenger} from "@lattice/interfaces/external/optimism/ICrossDomainMessenger.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.L1ToL2CrossDomainMessengerGatewayAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant L1_TO_L2_CROSS_DOMAIN_MESSENGER_GATEWAY_ADAPTER_STORAGE_SLOT =
    0xba3de3e77bc32833730368f3190597d7121922af189304a06067265b4d53a500;

/// @dev ERC-165 map slot for `IERC7786GatewaySource` (`0x11967553`). SHARED by all gateway adapters —
///      `keccak256(abi.encode(bytes4(0x11967553), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC7786GATEWAYSOURCE_SLOT =
    0x3c75b8ea75c097979221eb9302e2f0f6009b4ffe0a7198db5dc29979e09ea0e3;

/// @dev The canonical OP Stack L2 `CrossDomainMessenger` predeploy — fixed on every OP Stack chain. Handles the
///      L2 side of both deposits (L1->L2) and withdrawals (L2->L1).
///      PRE-MAINNET: re-verify this address (and the message encoding) against the then-current
///      `ethereum-optimism/optimism` `contracts-bedrock` release before ANY production deploy.
address constant L2_CROSS_DOMAIN_MESSENGER = 0x4200000000000000000000000000000000000007;

/// @notice ERC-7201 namespaced storage for the L1<->L2 CrossDomainMessenger gateway adapter.
/// @custom:storage-location erc7201:lattice.storage.L1ToL2CrossDomainMessengerGatewayAdapter
struct L1ToL2CrossDomainMessengerGatewayAdapterStorage {
    /// @notice The paired-domain (counterpart) chain id (0 = unset). A canonical L1<->L2 pair has exactly ONE
    ///         other domain, so there is no chainId map. APPEND-ONLY.
    uint256 _counterpartChainId;
    /// @notice Trusted counterpart gateway adapter (the sibling adapter on the paired domain; 0 = unset).
    ///         APPEND-ONLY.
    address _counterpartAdapter;
    /// @notice The `minGasLimit` the messenger relays outbound messages with. APPEND-ONLY.
    uint32 _minGasLimit;
    /// @notice Replay guard: the set of consumed message ids. Single counterpart, so keyed by id alone.
    ///         APPEND-ONLY.
    mapping(bytes32 id => bool used) _executed;
    /// @notice Monotonic outbound counter. The messenger's `sendMessage` returns VOID (no per-message id to the
    ///         delivery target), so each dispatched message carries this source-minted nonce, giving a
    ///         globally-unique (counterpart, nonce) id on delivery (matching the CCIP/LayerZero/Wormhole siblings).
    uint256 _outboundNonce;
}

/// @title L1ToL2CrossDomainMessengerGatewayAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Optimism (https://github.com/ethereum-optimism/optimism)
/// @notice Logic + ERC-7201 storage for the canonical OP Stack L1<->L2 `CrossDomainMessenger` ERC-7786 gateway
///         adapter. `sendMessage` wraps the ERC-7930 envelope as the calldata the messenger will execute on the
///         counterpart adapter and dispatches via `messenger.sendMessage` (no fee — the message is relayed on the
///         other domain); `receiveCrossChainMessage` is the messenger-invoked delivery callback that authenticates
///         the counterpart out-of-band via `xDomainMessageSender`, de-duplicates, and delivers to the ERC-7930
///         recipient. Carries BOTH deposits (L1->L2) and withdrawals (L2->L1); the adapter is direction-agnostic.
/// @dev INVERTED INBOUND AUTH: the adapter's inbound function is the `_target` the messenger CALLs during relay, so
///      `msg.sender` is the L2 messenger predeploy (NOT the counterpart gateway). Trust is therefore established by
///      reading the authenticated counterpart sender back from `messenger.xDomainMessageSender()` and matching it
///      to the configured (non-zero) counterpart adapter. The messenger self-dedups on the message hash (relay
///      reverts on replay via `successfulMessages`), so the per-envelope guard here is cheap defense-in-depth
///      rather than the primary replay defense. Wire message =
///      `abi.encodeCall(receiveCrossChainMessage, (senderInterop, recipient, payload, nonce))`.
library L1ToL2CrossDomainMessengerGatewayAdapterLib {
    function l1ToL2CrossDomainMessengerGatewayAdapterStorage()
        internal
        pure
        returns (L1ToL2CrossDomainMessengerGatewayAdapterStorage storage $)
    {
        assembly {
            $.slot := L1_TO_L2_CROSS_DOMAIN_MESSENGER_GATEWAY_ADAPTER_STORAGE_SLOT
        }
    }

    /// @notice Seeds the fixed counterpart + relay gas and registers the gateway-source ERC-165 id. The messenger
    ///         is the fixed predeploy constant, so there is no endpoint/router to persist at init.
    /// @param counterpartChainId The paired-domain chain id.
    /// @param counterpartAdapter The sibling adapter on the paired domain (must be non-zero).
    /// @param minGasLimit_       The `minGasLimit` the messenger relays outbound messages with.
    function __L1ToL2CrossDomainMessengerGatewayAdapter_init(
        uint256 counterpartChainId,
        address counterpartAdapter,
        uint32 minGasLimit_
    ) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        _setCounterpart(counterpartChainId, counterpartAdapter);
        _setMinGasLimit(minGasLimit_);
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
        return L2_CROSS_DOMAIN_MESSENGER;
    }

    function counterpartChainId() internal view returns (uint256) {
        return l1ToL2CrossDomainMessengerGatewayAdapterStorage()._counterpartChainId;
    }

    function counterpartAdapter() internal view returns (address) {
        return l1ToL2CrossDomainMessengerGatewayAdapterStorage()._counterpartAdapter;
    }

    function minGasLimit() internal view returns (uint32) {
        return l1ToL2CrossDomainMessengerGatewayAdapterStorage()._minGasLimit;
    }

    /// @notice No `sendMessage` attributes are supported by this adapter: relay gas is a fixed adapter config
    ///         (`_minGasLimit`), so there is no per-message gas config to attach.
    function supportsAttribute(bytes4) internal pure returns (bool) {
        return false;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    function setCounterpart(uint256 chainId, address adapter) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _setCounterpart(chainId, adapter);
    }

    function setMinGasLimit(uint32 newMinGasLimit) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _setMinGasLimit(newMinGasLimit);
    }

    /// @dev Unguarded counterpart write shared by init + the admin setter. Rejects a zero counterpart adapter so
    ///      inbound auth can never be satisfied by an unconfigured (zero) sender.
    function _setCounterpart(uint256 chainId, address adapter) private {
        if (adapter == address(0)) revert IL1ToL2CrossDomainMessengerGatewayAdapter.InvalidCounterpartAdapter();
        L1ToL2CrossDomainMessengerGatewayAdapterStorage storage $ = l1ToL2CrossDomainMessengerGatewayAdapterStorage();
        $._counterpartChainId = chainId;
        $._counterpartAdapter = adapter;
        emit IL1ToL2CrossDomainMessengerGatewayAdapter.CounterpartConfigured(chainId, adapter);
    }

    /// @dev Unguarded min-gas write shared by init + the admin setter.
    function _setMinGasLimit(uint32 newMinGasLimit) private {
        // Reject a zero relay gas limit (delivery would out-of-gas at the recipient handshake). Admins must still
        // provision a value adequate for the recipient's `receiveMessage` cost — an L2->L1/L1->L2 message's relay
        // gas is fixed at dispatch, so an under-provisioned limit strands delivery until reconfigured.
        if (newMinGasLimit == 0) revert IL1ToL2CrossDomainMessengerGatewayAdapter.InvalidMinGasLimit();
        l1ToL2CrossDomainMessengerGatewayAdapterStorage()._minGasLimit = newMinGasLimit;
        emit IL1ToL2CrossDomainMessengerGatewayAdapter.MinGasLimitConfigured(newMinGasLimit);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   SEND
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice ERC-7786 source. Wraps the ERC-7930 envelope as the calldata the messenger will execute on the
    ///         counterpart adapter and dispatches it via `messenger.sendMessage`. Charges NO fee: the message is
    ///         relayed on the other domain and the messenger takes no native value here, so a non-empty `msg.value`
    ///         is rejected. `messenger.sendMessage` returns VOID, so the ERC-7786 `sendId` is derived locally as
    ///         `keccak256(abi.encode(counterpartChainId, nonce))` — the (source, nonce) unique-id scheme using the
    ///         counterpart as the id namespace.
    /// @dev No attributes are supported — any attribute reverts {UnsupportedAttribute}.
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        internal
        returns (bytes32)
    {
        if (attributes.length != 0) revert IERC7786GatewaySource.UnsupportedAttribute(bytes4(attributes[0]));
        // The messenger charges no native fee here; reject stray value so it is never trapped in the Diamond.
        if (msg.value != 0) revert IL1ToL2CrossDomainMessengerGatewayAdapter.UnexpectedValue(msg.value);

        // Envelope carries a source-owned monotonic nonce (`$._outboundNonce++`) so the delivery id is globally
        // unique per (counterpart, nonce) rather than envelope content — otherwise two byte-identical-but-distinct
        // messages would collide on delivery (one permanently dropped) and the recipient would see a non-unique id.
        // Dispatch is block-scoped so the routing locals free before the emit (non-via-IR stack budget).
        bytes32 id;
        {
            (uint256 destChainId,) = InteroperableAddress.parseEvmV1(recipient);
            L1ToL2CrossDomainMessengerGatewayAdapterStorage storage $ =
                l1ToL2CrossDomainMessengerGatewayAdapterStorage();
            if (destChainId != $._counterpartChainId) {
                revert IL1ToL2CrossDomainMessengerGatewayAdapter.UnknownDestinationChain(destChainId);
            }
            address counterpart = $._counterpartAdapter;
            if (counterpart == address(0)) {
                revert IL1ToL2CrossDomainMessengerGatewayAdapter.InvalidCounterpartAdapter();
            }
            uint256 nonce = $._outboundNonce++;
            bytes memory message = abi.encodeCall(
                IL1ToL2CrossDomainMessengerGatewayAdapter.receiveCrossChainMessage,
                (InteroperableAddress.formatEvmV1(block.chainid, msg.sender), recipient, payload, nonce)
            );
            ICrossDomainMessenger(L2_CROSS_DOMAIN_MESSENGER).sendMessage(counterpart, message, $._minGasLimit);
            // Namespace the id by the SOURCE chain (this one) + nonce: this equals what the counterpart derives on
            // receipt (its `_counterpartChainId` is THIS chain), so the send-side sendId and the receive-side id
            // for one message match, and this adapter's outbound ids (source = this chain) never collide with its
            // inbound ids (source = the counterpart chain).
            id = keccak256(abi.encode(block.chainid, nonce));
        }

        emit IERC7786GatewaySource.MessageSent(
            id, InteroperableAddress.formatEvmV1(block.chainid, msg.sender), recipient, payload, msg.value, attributes
        );
        return id;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  RECEIVE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Messenger-invoked delivery callback (INVERTED AUTH). Authenticates: (1) `msg.sender` is the L2
    ///         messenger predeploy; (2) the authenticated counterpart sender read from `xDomainMessageSender()`
    ///         matches the configured (non-zero) counterpart adapter. De-dups per id marking BEFORE delivery
    ///         (strict CEI), then delivers to the ERC-7930 recipient after asserting it targets THIS chain.
    /// @dev The per-envelope guard is defense-in-depth: the messenger already self-dedups on the message hash,
    ///      reverting relay on replay via `successfulMessages`. L2->L1 (withdrawal) messages reach this callback
    ///      only after the withdrawal challenge window elapses (finalization handled off-chain by the messenger).
    function receiveCrossChainMessage(
        bytes calldata sender,
        bytes calldata recipient,
        bytes calldata payload,
        uint256 nonce
    ) internal {
        if (msg.sender != L2_CROSS_DOMAIN_MESSENGER) {
            revert IL1ToL2CrossDomainMessengerGatewayAdapter.NotMessenger(msg.sender);
        }

        L1ToL2CrossDomainMessengerGatewayAdapterStorage storage $ = l1ToL2CrossDomainMessengerGatewayAdapterStorage();

        // INVERTED AUTH + CEI replay guard, then the globally-unique delivery id. Block-scoped so the auth locals
        // free before delivery (non-via-IR stack budget). The id is derived from the fixed counterpart chain + the
        // source-minted nonce (NOT envelope content), so two byte-identical-but-distinct messages get distinct ids
        // (neither dropped) and the recipient sees a unique id. Redundant defense-in-depth over the messenger's own
        // self-dedup; marked BEFORE delivery.
        bytes32 id;
        {
            // Read the authenticated counterpart sender back from the messenger; reject an unconfigured counterpart
            // (adapter 0) explicitly, so a zero-sender delivery can never satisfy auth against an unconfigured pair.
            address counterpart = $._counterpartAdapter;
            address crossSender = ICrossDomainMessenger(L2_CROSS_DOMAIN_MESSENGER).xDomainMessageSender();
            if (counterpart == address(0) || crossSender != counterpart) {
                revert IL1ToL2CrossDomainMessengerGatewayAdapter.InvalidOriginGateway(crossSender);
            }
            id = keccak256(abi.encode($._counterpartChainId, nonce));
            if ($._executed[id]) {
                revert IL1ToL2CrossDomainMessengerGatewayAdapter.MessageAlreadyExecuted(id);
            }
            $._executed[id] = true;
        }

        // A well-behaved counterpart adapter only ever routes messages whose recipient targets THIS chain; reject
        // anything else so a rogue/misconfigured counterpart cannot misdirect delivery. Scoped so only `target`
        // survives to the delivery call.
        address target;
        {
            (uint256 recipientChainId, address target_) = InteroperableAddress.parseEvmV1(recipient);
            if (recipientChainId != block.chainid) {
                revert IL1ToL2CrossDomainMessengerGatewayAdapter.WrongDestinationChain(recipientChainId);
            }
            target = target_;
        }
        if (IERC7786Recipient(target).receiveMessage(id, sender, payload) != IERC7786Recipient.receiveMessage.selector)
        {
            revert IL1ToL2CrossDomainMessengerGatewayAdapter.RecipientExecutionFailed();
        }
    }
}
