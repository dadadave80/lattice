// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IHyperlaneGatewayAdapter} from "@lattice/interfaces/crosschain/IHyperlaneGatewayAdapter.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/IERC7786.sol";
import {IMailbox} from "@lattice/interfaces/external/IMailbox.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.HyperlaneGatewayAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant HYPERLANE_GATEWAY_ADAPTER_STORAGE_SLOT =
    0x8a4b1302312d119abfdb0305131f00457b784ef22f6824db37cbaed84bba5600;

/// @dev ERC-165 map slot for `IERC7786GatewaySource` (`0x11967553`). SHARED by all gateway adapters —
///      `keccak256(abi.encode(bytes4(0x11967553), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC7786GATEWAYSOURCE_SLOT =
    0x3c75b8ea75c097979221eb9302e2f0f6009b4ffe0a7198db5dc29979e09ea0e3;

/// @dev 0xb4f23f37 is `type(IHyperlaneGatewayAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xb4f23f37), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IHYPERLANEGATEWAYADAPTER_SLOT =
    0xda64faf279e491b8914ea1bd5a229e6b869c7ceecd7af74ddf271e5df1381612;

/// @notice ERC-7201 namespaced storage for the Hyperlane gateway adapter.
/// @custom:storage-location erc7201:lattice.storage.HyperlaneGatewayAdapter
struct HyperlaneGatewayAdapterStorage {
    /// @notice The Hyperlane Mailbox (OZ-style immutable → Diamond storage). APPEND-ONLY.
    address _mailbox;
    /// @notice EVM chainId => Hyperlane domain (0 = unset). Admin-registered, never inferred. APPEND-ONLY.
    mapping(uint256 chainId => uint32 domain) _chainIdToDomain;
    /// @notice Hyperlane domain => EVM chainId (0 = unset). Admin-registered, never inferred. APPEND-ONLY.
    mapping(uint32 domain => uint256 chainId) _domainToChainId;
    /// @notice Trusted 32-byte remote (counterpart adapter) per EVM chainId (0 = unset; tunable). APPEND-ONLY.
    mapping(uint256 chainId => bytes32 remote) _trustedRemotes;
    /// @notice Per-destination `handle` gas limit (0 = unset ⇒ adapter default; tunable). APPEND-ONLY.
    mapping(uint256 chainId => uint256 gasLimit) _destGasLimit;
    /// @notice Monotonic outbound counter. Hyperlane's `handle` exposes no messageId to the recipient, so each
    ///         dispatched envelope carries this source-minted nonce, giving a globally-unique (source, nonce)
    ///         id on delivery (matching the ZetaChain/L2ToL2 siblings' unique-id semantics). APPEND-ONLY.
    uint256 _lastNonce;
    /// @notice Replay guard: per source chainId, the set of consumed sendIds. APPEND-ONLY.
    mapping(uint256 chainId => mapping(bytes32 sendId => bool executed)) _executed;
}

/// @title HyperlaneGatewayAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Hyperlane (https://github.com/hyperlane-xyz/hyperlane-monorepo)
/// @notice Logic + ERC-7201 storage for the Hyperlane ERC-7786 gateway adapter. `sendMessage` wraps the
///         ERC-7930 envelope with a source-minted nonce and dispatches it via the Mailbox's 4-arg `dispatch`
///         (default hook + synthesized StandardHookMetadata); `handle` is the Mailbox-gated delivery callback
///         that validates the origin domain + trusted remote, de-duplicates per (chainId, sendId), and
///         delivers to the ERC-7930 recipient. EVM chains only. Hyperlane routes by `uint32` domain — usually
///         the EVM chainId but NOT guaranteed, so the map is admin-registered, never inferred.
/// @dev Wire message = `abi.encode(senderInteropAddr, recipientInteropAddr, innerPayload, nonce)`; the
///      Mailbox `recipientAddress` targets the trusted 32-byte remote, which forwards to the final recipient.
///      The hook metadata is Hyperlane `StandardHookMetadata` variant 1 synthesized INLINE (no hook-lib
///      dependency): `variant(uint16=1) || msgValue(uint256=0) || gasLimit(uint256) || refundAddress(address
///      = the sending user)` — overpaid IGP fees refund to the user, never to the Diamond. v1 uses the
///      Mailbox DEFAULT ISM (no `ISpecifiesInterchainSecurityModule`); pinning a Lattice-custom ISM by adding
///      `interchainSecurityModule()` to the facet later is a compatible additive follow-up.
library HyperlaneGatewayAdapterLib {
    /// @dev StandardHookMetadata variant 1 (the only variant the default hook stack understands).
    uint16 private constant METADATA_VARIANT = 1;
    /// @dev `handle` gas limit used when a destination has no admin-configured gas limit. Sized for envelope
    ///      decode + auth + dedup + a typical `receiveMessage` (Hyperlane's own bare default of 50k is too
    ///      thin for the recipient hop).
    uint256 internal constant DEFAULT_DESTINATION_GAS = 200_000;

    function hyperlaneGatewayAdapterStorage() internal pure returns (HyperlaneGatewayAdapterStorage storage $) {
        assembly {
            $.slot := HYPERLANE_GATEWAY_ADAPTER_STORAGE_SLOT
        }
    }

    /// @notice Stores the Mailbox (zero reverts {HyperlaneZeroMailbox} — an unconfigured adapter must not
    ///         exist) and registers the gateway-source + adapter ERC-165 ids.
    function __HyperlaneGatewayAdapter_init(address mailbox_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        if (mailbox_ == address(0)) revert IHyperlaneGatewayAdapter.HyperlaneZeroMailbox();
        hyperlaneGatewayAdapterStorage()._mailbox = mailbox_;
        registerInterfaces();
    }

    /// @notice Writes `true` to the SHARED IERC7786GatewaySource ERC-165 map slot (0x11967553 → ...; same
    ///         slot the CCIP/LayerZero/Wormhole/Axelar adapters register — a Diamond mounts at most one
    ///         gateway) and to the adapter's own IHyperlaneGatewayAdapter map slot.
    function registerInterfaces() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC7786GATEWAYSOURCE_SLOT, true)
            sstore(ERC165_MAP_IHYPERLANEGATEWAYADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function mailbox() internal view returns (address) {
        return hyperlaneGatewayAdapterStorage()._mailbox;
    }

    function domainOf(uint256 chainId) internal view returns (uint32) {
        return hyperlaneGatewayAdapterStorage()._chainIdToDomain[chainId];
    }

    function chainIdOf(uint32 domain) internal view returns (uint256) {
        return hyperlaneGatewayAdapterStorage()._domainToChainId[domain];
    }

    function trustedRemoteOf(uint256 chainId) internal view returns (bytes32) {
        return hyperlaneGatewayAdapterStorage()._trustedRemotes[chainId];
    }

    function destGasLimitOf(uint256 chainId) internal view returns (uint256) {
        return hyperlaneGatewayAdapterStorage()._destGasLimit[chainId];
    }

    /// @notice No `sendMessage` attributes are supported by this adapter (per-dest gas is admin-configured).
    function supportsAttribute(bytes4) internal pure returns (bool) {
        return false;
    }

    /// @notice Quotes the Mailbox fee to send `payload` to `recipient` (ERC-7930), synthesizing the same wire
    ///         envelope (with the NEXT nonce) + StandardHookMetadata a real send would dispatch.
    function quoteFee(bytes calldata recipient, bytes calldata payload) internal view returns (uint256) {
        HyperlaneGatewayAdapterStorage storage $ = hyperlaneGatewayAdapterStorage();
        (uint32 domain, bytes32 remote, uint256 gasLimit) = _resolveDestination($, recipient);
        return IMailbox($._mailbox)
            .quoteDispatch(
                domain,
                remote,
                abi.encode(
                    InteroperableAddress.formatEvmV1(block.chainid, msg.sender), recipient, payload, $._lastNonce + 1
                ),
                _buildMetadata(gasLimit, msg.sender)
            );
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers an EVM chainId ↔ Hyperlane domain equivalence (both directions). FAIL-LOUD identity
    ///         admin: an already-mapped chainId OR domain reverts — identities are never remapped. Admin only.
    function registerDomain(uint256 chainId, uint32 domain) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (domain == 0) revert IHyperlaneGatewayAdapter.HyperlaneZeroDomain();
        HyperlaneGatewayAdapterStorage storage $ = hyperlaneGatewayAdapterStorage();
        if ($._chainIdToDomain[chainId] != 0 || $._domainToChainId[domain] != 0) {
            revert IHyperlaneGatewayAdapter.HyperlaneDomainAlreadyRegistered(chainId, domain);
        }
        $._chainIdToDomain[chainId] = domain;
        $._domainToChainId[domain] = chainId;
        emit IHyperlaneGatewayAdapter.RegisteredDomain(chainId, domain);
    }

    /// @notice Sets the trusted 32-byte remote (counterpart adapter) for a chain. TUNABLE (updatable), but
    ///         never zero — clearing a corridor is not supported in v1. Admin only.
    function registerRemote(uint256 chainId, bytes32 remote) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (remote == bytes32(0)) revert IHyperlaneGatewayAdapter.HyperlaneZeroRemote();
        hyperlaneGatewayAdapterStorage()._trustedRemotes[chainId] = remote;
        emit IHyperlaneGatewayAdapter.RegisteredRemote(chainId, remote);
    }

    /// @notice Configures a destination's `handle` gas limit. TUNABLE; 0 = fall back to
    ///         {DEFAULT_DESTINATION_GAS} at send time. Admin only.
    function configureDestination(uint256 chainId, uint256 gasLimit) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        hyperlaneGatewayAdapterStorage()._destGasLimit[chainId] = gasLimit;
        emit IHyperlaneGatewayAdapter.ConfiguredDestination(chainId, gasLimit);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   SEND
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice ERC-7786 source. Quotes the Mailbox fee (typed {HyperlaneInsufficientFee} on shortfall), then
    ///         dispatches immediately via the 4-arg `dispatch`, forwarding `msg.value` WHOLE — the default
    ///         hook refunds any surplus to the metadata refundAddress (`msg.sender`, the sending user), so the
    ///         Diamond never holds or spends fee funds.
    /// @dev No attributes are supported — any attribute reverts {UnsupportedAttribute}. The envelope carries a
    ///      source-owned monotonic nonce (`++$._lastNonce`) so the delivery id is globally unique per
    ///      (source, nonce) rather than envelope content — otherwise two byte-identical-but-distinct messages
    ///      would collide on delivery (one permanently dropped). Returns the suite-level
    ///      `sendId = keccak256(abi.encode(block.chainid, nonce))`; the Hyperlane `messageId` is surfaced via
    ///      {HyperlaneMessageDispatched}.
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        internal
        returns (bytes32)
    {
        if (attributes.length != 0) revert IERC7786GatewaySource.UnsupportedAttribute(bytes4(attributes[0]));

        // Dispatch is block-scoped so the routing locals free before the emits (non-via-IR stack budget).
        bytes32 sendId;
        {
            HyperlaneGatewayAdapterStorage storage $ = hyperlaneGatewayAdapterStorage();
            (uint32 domain, bytes32 remote, uint256 gasLimit) = _resolveDestination($, recipient);
            uint256 nonce = ++$._lastNonce;
            sendId = keccak256(abi.encode(block.chainid, nonce));

            bytes memory envelope =
                abi.encode(InteroperableAddress.formatEvmV1(block.chainid, msg.sender), recipient, payload, nonce);
            bytes memory metadata = _buildMetadata(gasLimit, msg.sender);

            address mailbox_ = $._mailbox;
            uint256 fee = IMailbox(mailbox_).quoteDispatch(domain, remote, envelope, metadata);
            if (msg.value < fee) revert IHyperlaneGatewayAdapter.HyperlaneInsufficientFee(msg.value, fee);

            // Forward msg.value whole: the default hook refunds overpayment to the metadata refundAddress.
            bytes32 messageId = IMailbox(mailbox_).dispatch{value: msg.value}(domain, remote, envelope, metadata);
            emit IHyperlaneGatewayAdapter.HyperlaneMessageDispatched(sendId, messageId, domain);
        }

        emit IERC7786GatewaySource.MessageSent(
            sendId,
            InteroperableAddress.formatEvmV1(block.chainid, msg.sender),
            recipient,
            payload,
            msg.value,
            attributes
        );
        return sendId;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  RECEIVE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Mailbox delivery callback: DUAL AUTH — `msg.sender` must be the Mailbox AND the 32-byte
    ///         `sender` must equal the trusted remote registered for the origin domain's chain (fail-closed on
    ///         an unregistered domain, i.e. chainId 0, or an unset remote). De-dups per (chainId, sendId),
    ///         marking BEFORE the external delivery (checks-effects-interactions), then delivers to the
    ///         ERC-7930 recipient encoded in the envelope.
    /// @dev The Mailbox's own `delivered` map is the PROTOCOL-level replay guard (`process` reverts on
    ///      redelivery); the per-(chainId, sendId) guard here is defense-in-depth at the suite convention
    ///      level, keyed by the source-minted nonce id every sibling adapter uses. `handle` is forced payable
    ///      by {IMessageRecipient}, but the adapter never expects value-bearing messages in v1 — stray value
    ///      reverts {HyperlaneUnexpectedValue} instead of being trapped in the Diamond.
    function handle(uint32 origin, bytes32 sender, bytes calldata message) internal {
        if (msg.value != 0) revert IHyperlaneGatewayAdapter.HyperlaneUnexpectedValue(msg.value);
        HyperlaneGatewayAdapterStorage storage $ = hyperlaneGatewayAdapterStorage();
        if (msg.sender != $._mailbox) revert IHyperlaneGatewayAdapter.HyperlaneNotMailbox(msg.sender);

        uint256 chainId = $._domainToChainId[origin];
        bytes32 remote = $._trustedRemotes[chainId];
        // Reject an unregistered origin (chainId 0) or an unconfigured remote (bytes32(0)) explicitly, so a
        // domain registered before its remote can never satisfy auth against a zero-sender delivery.
        if (chainId == 0 || remote == bytes32(0) || remote != sender) {
            revert IHyperlaneGatewayAdapter.HyperlaneInvalidOriginGateway(origin, sender);
        }

        (bytes memory senderInterop, bytes memory recipient, bytes memory inner, uint256 nonce) =
            abi.decode(message, (bytes, bytes, bytes, uint256));

        // CEI replay guard on the globally-unique (source, nonce) delivery id; marked BEFORE delivery.
        bytes32 sendId = keccak256(abi.encode(chainId, nonce));
        if ($._executed[chainId][sendId]) {
            revert IHyperlaneGatewayAdapter.HyperlaneMessageAlreadyExecuted(chainId, sendId);
        }
        $._executed[chainId][sendId] = true;

        (uint256 recipientChainId, address target) = InteroperableAddress.parseEvmV1(recipient);
        // Defense-in-depth: the source routes by the recipient's chainId, so a well-behaved remote only ever
        // delivers messages whose recipient targets THIS chain; a rogue/buggy trusted remote cannot misdirect.
        if (recipientChainId != block.chainid) {
            revert IHyperlaneGatewayAdapter.HyperlaneWrongDestinationChain(recipientChainId);
        }
        if (
            IERC7786Recipient(target).receiveMessage(sendId, senderInterop, inner)
                != IERC7786Recipient.receiveMessage.selector
        ) {
            revert IHyperlaneGatewayAdapter.HyperlaneRecipientExecutionFailed();
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Resolves `recipient`'s chain into (domain, trusted remote, effective gas limit).
    /// @dev Reverts {HyperlaneUnknownDestinationChain} if the domain or remote is unset. An unset gas limit
    ///      falls back to {DEFAULT_DESTINATION_GAS} (mirroring the per-dest admin gas of the LZ sibling, with
    ///      a default instead of a hard revert — Hyperlane's default hook prices gas from the metadata).
    function _resolveDestination(HyperlaneGatewayAdapterStorage storage $, bytes calldata recipient)
        private
        view
        returns (uint32 domain, bytes32 remote, uint256 gasLimit)
    {
        (uint256 chainId,) = InteroperableAddress.parseEvmV1(recipient);
        domain = $._chainIdToDomain[chainId];
        remote = $._trustedRemotes[chainId];
        if (domain == 0 || remote == bytes32(0)) {
            revert IHyperlaneGatewayAdapter.HyperlaneUnknownDestinationChain(chainId);
        }
        gasLimit = $._destGasLimit[chainId];
        if (gasLimit == 0) gasLimit = DEFAULT_DESTINATION_GAS;
    }

    /// @notice Synthesizes Hyperlane `StandardHookMetadata` variant 1 INLINE (no hook-lib dependency):
    ///         `variant(uint16=1) || msgValue(uint256=0) || gasLimit(uint256) || refundAddress(address)`.
    ///         msgValue is always 0 (plain messages only in v1); `refundAddress` is the sending user, so
    ///         overpaid IGP fees refund there.
    function _buildMetadata(uint256 gasLimit, address refundAddress) private pure returns (bytes memory) {
        return abi.encodePacked(METADATA_VARIANT, uint256(0), gasLimit, refundAddress);
    }
}
