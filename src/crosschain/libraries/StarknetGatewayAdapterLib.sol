// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {NonEvmAddress} from "@lattice/crosschain/libraries/NonEvmAddress.sol";
import {IStarknetGatewayAdapter} from "@lattice/interfaces/crosschain/IStarknetGatewayAdapter.sol";
import {IStarknetMessaging} from "@lattice/interfaces/external/IStarknetMessaging.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.StarknetGatewayAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant STARKNET_GATEWAY_ADAPTER_STORAGE_SLOT =
    0x3f9fd8bc99bc5c4e4ff64e899fbe5f73a1a0f6c02aaa904e7184494718213e00;

/// @dev 0x7dfd78ca is `type(IStarknetGatewayAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x7dfd78ca), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ISTARKNETGATEWAYADAPTER_SLOT =
    0xbcf162df5dae478299124881124442c9a950f7c7a4c96c5d289b1c3a20b1dd53;

/// @notice ERC-7201 namespaced storage for the Starknet L1 <-> L2 gateway adapter.
/// @custom:storage-location erc7201:lattice.storage.StarknetGatewayAdapter
struct StarknetGatewayAdapterStorage {
    /// @notice The Starknet core (`StarknetMessaging`) contract on this chain (configured at init). APPEND-ONLY.
    address _starknetCore;
    /// @notice The ERC-7930 chain reference this adapter accepts (UTF-8 chain-id string, e.g. `SN_MAIN`,
    ///         configured at init). APPEND-ONLY.
    bytes _expectedChainReference;
    /// @notice L2 target felt => registered `l1_handler` selector (0 = unregistered). APPEND-ONLY.
    mapping(uint256 l2Target => uint256 selector) _l1HandlerSelector;
    /// @notice L2 sender felt => trusted flag for the inbound consume path. APPEND-ONLY.
    mapping(uint256 fromAddress => bool trusted) _trustedL2Senders;
    /// @notice In-flight outbound message hash => the L1 initiator allowed to cancel it. APPEND-ONLY.
    mapping(bytes32 msgHash => address initiator) _initiators;
}

/// @title StarknetGatewayAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Starknet (https://github.com/starkware-libs/cairo-lang)
/// @notice Logic + ERC-7201 storage for the L1-side Starknet L1 <-> L2 connector. Outbound {sendMessage}
///         parses the ERC-7930 felt252 recipient, felt-chunk encodes the payload, escrows `msg.value` as the
///         non-refundable message fee via `sendMessageToL2`, and records the caller as the message's initiator;
///         {startCancellation}/{cancel} re-derive the message hash from the original inputs and are gated to
///         that initiator (the DIAMOND is the L1 sender on the core, so cancellation authority must be
///         re-derived at the facet level — an ungated cancel would let anyone grief in-flight messages);
///         inbound {consumeMessage} is a permissionless keeper-driven PULL against the core's per-message
///         counter, allow-listed by trusted L2 sender.
/// @dev TRUST MODEL: the Starknet core is the authenticator on BOTH directions — outbound it escrows the fee
///      and mints the nonce, inbound `consumeMessageFromL2` only consumes messages addressed to `msg.sender`
///      (the diamond) and reverts when the counter is zero. The fee is ESCROWED AND NEVER REFUNDED, cancellation
///      included. DELIBERATELY BESPOKE (not `IERC7786GatewaySource`): the inbound path is a pull-based consume
///      against a counter (no message id to dedup), attributes cannot express the escrowed fee + cancellation
///      lifecycle, and the wire payload is a felt array — see {IStarknetGatewayAdapter}. Emit-only inbound in
///      v1; never routed into CrosschainLink / OpenBridge.
library StarknetGatewayAdapterLib {
    /// @dev One byte more than a felt chunk's 31-byte capacity — every valid chunk is `< 2**248`.
    uint256 private constant CHUNK_BOUND = 1 << 248;

    function starknetGatewayAdapterStorage() internal pure returns (StarknetGatewayAdapterStorage storage $) {
        assembly {
            $.slot := STARKNET_GATEWAY_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Configures the Starknet core + expected chain reference and registers the
    ///         IStarknetGatewayAdapter ERC-165 id.
    /// @dev Reverts {StarknetZeroAddress} on a zero core, {StarknetEmptyChainReference} on an empty chain
    ///      reference (an unconfigured adapter must not exist). Called inside the diamond initializing window.
    function __StarknetGatewayAdapter_init(address starknetCore_, bytes memory expectedChainReference_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        if (starknetCore_ == address(0)) revert IStarknetGatewayAdapter.StarknetZeroAddress();
        if (expectedChainReference_.length == 0) revert IStarknetGatewayAdapter.StarknetEmptyChainReference();
        StarknetGatewayAdapterStorage storage $ = starknetGatewayAdapterStorage();
        $._starknetCore = starknetCore_;
        $._expectedChainReference = expectedChainReference_;
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for `IStarknetGatewayAdapter`.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ISTARKNETGATEWAYADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function starknetCore() internal view returns (address) {
        return starknetGatewayAdapterStorage()._starknetCore;
    }

    function expectedChainReference() internal view returns (bytes memory) {
        return starknetGatewayAdapterStorage()._expectedChainReference;
    }

    function l1HandlerSelector(uint256 l2Target) internal view returns (uint256) {
        return starknetGatewayAdapterStorage()._l1HandlerSelector[l2Target];
    }

    function isTrustedL2Sender(uint256 fromAddress) internal view returns (bool) {
        return starknetGatewayAdapterStorage()._trustedL2Senders[fromAddress];
    }

    function initiatorOf(bytes32 msgHash) internal view returns (address) {
        return starknetGatewayAdapterStorage()._initiators[msgHash];
    }

    /// @notice The Starknet selector (`starknet_keccak`) of an entry-point `name`: keccak256 masked to its low
    ///         250 bits. `l1_handler` selectors are starknet_keccak values of the handler's Cairo name.
    function starknetSelector(string calldata name) internal pure returns (uint256) {
        return uint256(keccak256(bytes(name))) & ((1 << 250) - 1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the `l1_handler` selector to invoke when sending to `l2Target`. Both must be non-zero
    ///         felt252s ({StarknetNotAFelt}) — selectors are starknet_keccak values that CANNOT be derived from
    ///         the ERC-7930 address, so each L2 target is registered with its handler by the admin. Admin only.
    function registerL2Handler(uint256 l2Target, uint256 selector) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _checkFelt(l2Target);
        _checkFelt(selector);
        starknetGatewayAdapterStorage()._l1HandlerSelector[l2Target] = selector;
        emit IStarknetGatewayAdapter.RegisteredL2Handler(l2Target, selector);
    }

    /// @notice Sets the trusted flag of the L2 sender `fromAddress` (a non-zero felt252) for the inbound
    ///         consume path. Admin only.
    function setTrustedL2Sender(uint256 fromAddress, bool trusted) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _checkFelt(fromAddress);
        starknetGatewayAdapterStorage()._trustedL2Senders[fromAddress] = trusted;
        emit IStarknetGatewayAdapter.SetTrustedL2Sender(fromAddress, trusted);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   SEND
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sends `payload` (felt-chunk encoded) to the ERC-7930 Starknet `recipient`'s registered
    ///         `l1_handler`, forwarding `msg.value` as the message fee, and records `msg.sender` as the
    ///         message's initiator (the only party able to cancel it).
    /// @dev FEE WARNING: the fee is escrowed by the Starknet core and NEVER refunded — cancellation included.
    ///      The adapter only requires it to be non-zero ({StarknetZeroFee}); the core bounds the max
    ///      (`getMaxL1MsgFee`, bubbling `MAX_L1_MSG_FEE_EXCEEDED`). Fail-closed destination checks (mirroring
    ///      the Across/ZetaChain cross-check precedent): the chainType must be the starknet key
    ///      ({StarknetWrongChainType}) and the chain reference must equal the configured one
    ///      ({StarknetChainReferenceMismatch}). `nonReentrant` with CEI — the only effect (the initiator
    ///      record) depends on the core-returned `msgHash`, so it lands right after the call, inside the guard.
    function sendMessage(bytes calldata recipient, bytes calldata payload)
        internal
        returns (bytes32 msgHash, uint256 nonce)
    {
        ReentrancyGuardLib.nonReentrantBefore();
        StarknetGatewayAdapterStorage storage $ = starknetGatewayAdapterStorage();

        // --- Checks ---
        (uint256 toFelt, uint256 selector) = _parseAndCheckRecipient($, recipient);
        if (msg.value == 0) revert IStarknetGatewayAdapter.StarknetZeroFee();

        // --- Interactions/Effects: every payload felt is < 2**248 < FIELD_PRIME by construction. ---
        uint256[] memory felts = encodeFelts(payload);
        (msgHash, nonce) =
            IStarknetMessaging($._starknetCore).sendMessageToL2{value: msg.value}(toFelt, selector, felts);
        $._initiators[msgHash] = msg.sender;

        emit IStarknetGatewayAdapter.StarknetMessageSent(
            msg.sender, toFelt, selector, msgHash, nonce, msg.value, payload
        );
        ReentrancyGuardLib.nonReentrantAfter();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                CANCELLATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Starts the two-step cancellation of a previously sent message. Initiator only.
    /// @dev The DIAMOND is the L1 sender on the core, so only the diamond can call the core's cancellation
    ///      entrypoints — authority is re-derived here: `toFelt`/`felts` are recomputed deterministically from
    ///      the ORIGINAL `recipient`/`payload`, the message hash is recomputed via
    ///      `core.l1ToL2MsgHash(address(this), ...)`, and the caller must be the recorded initiator
    ///      ({StarknetNotInitiator}) BEFORE anything is forwarded to the core. The `selector` is the SEND-TIME
    ///      selector, passed EXPLICITLY (it is emitted in {StarknetMessageSent}) and deliberately NOT re-read
    ///      from the mutable `_l1HandlerSelector` registry — re-registering a target's handler while a message
    ///      is in flight would otherwise change the re-derived hash and permanently lock the initiator out of
    ///      cancelling (review finding). A wrong selector is harmless: it re-derives a different hash whose
    ///      initiator record is empty. The core enforces the `messageCancellationDelay()` wait before {cancel}.
    function startCancellation(bytes calldata recipient, uint256 selector, bytes calldata payload, uint256 nonce)
        internal
        returns (bytes32 msgHash)
    {
        ReentrancyGuardLib.nonReentrantBefore();
        StarknetGatewayAdapterStorage storage $ = starknetGatewayAdapterStorage();
        IStarknetMessaging core = IStarknetMessaging($._starknetCore);

        uint256 toFelt = _parseRecipientFelt($, recipient);
        _checkFelt(selector);
        uint256[] memory felts = encodeFelts(payload);
        msgHash = core.l1ToL2MsgHash(address(this), toFelt, selector, felts, nonce);
        if ($._initiators[msgHash] != msg.sender) {
            revert IStarknetGatewayAdapter.StarknetNotInitiator(msgHash, msg.sender);
        }

        core.startL1ToL2MessageCancellation(toFelt, selector, felts, nonce);
        emit IStarknetGatewayAdapter.StarknetCancellationStarted(msg.sender, msgHash, nonce);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Completes the cancellation started by {startCancellation} (same arguments), at least
    ///         `messageCancellationDelay()` seconds later. Initiator only; clears the initiator record on
    ///         success. The escrowed fee is NOT refunded. `selector` is the send-time selector (see
    ///         {startCancellation} for why it is explicit rather than registry-derived).
    function cancel(bytes calldata recipient, uint256 selector, bytes calldata payload, uint256 nonce)
        internal
        returns (bytes32 msgHash)
    {
        ReentrancyGuardLib.nonReentrantBefore();
        StarknetGatewayAdapterStorage storage $ = starknetGatewayAdapterStorage();
        IStarknetMessaging core = IStarknetMessaging($._starknetCore);

        uint256 toFelt = _parseRecipientFelt($, recipient);
        _checkFelt(selector);
        uint256[] memory felts = encodeFelts(payload);
        msgHash = core.l1ToL2MsgHash(address(this), toFelt, selector, felts, nonce);
        if ($._initiators[msgHash] != msg.sender) {
            revert IStarknetGatewayAdapter.StarknetNotInitiator(msgHash, msg.sender);
        }

        core.cancelL1ToL2Message(toFelt, selector, felts, nonce);
        delete $._initiators[msgHash];
        emit IStarknetGatewayAdapter.StarknetMessageCancelled(msg.sender, msgHash, nonce);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CONSUME
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Permissionless keeper-driven PULL: consumes an L2 -> L1 message from the trusted L2 sender
    ///         `fromAddress` addressed to this diamond ({StarknetUntrustedSender} otherwise). Emit-only in v1.
    /// @dev The core is the real authenticator — `consumeMessageFromL2` only consumes messages addressed to
    ///      `msg.sender` (the diamond) and reverts when the per-message counter is zero. COUNTER SEMANTICS:
    ///      duplicates are N DISTINCT consumes, NOT replays — each consume decrements a core-side counter, so
    ///      consuming the same payload twice requires the L2 to have SENT it twice. NOT routed into
    ///      CrosschainLink / OpenBridge (there is no message id to dedup or M-of-N confirm on).
    function consumeMessage(uint256 fromAddress, bytes calldata payload) internal returns (bytes32 msgHash) {
        ReentrancyGuardLib.nonReentrantBefore();
        StarknetGatewayAdapterStorage storage $ = starknetGatewayAdapterStorage();
        if (!$._trustedL2Senders[fromAddress]) {
            revert IStarknetGatewayAdapter.StarknetUntrustedSender(fromAddress);
        }
        // Same wire format both directions: the L2 side emits the felt-chunk encoding of the bytes payload.
        uint256[] memory felts = encodeFelts(payload);
        msgHash = IStarknetMessaging($._starknetCore).consumeMessageFromL2(fromAddress, felts);
        emit IStarknetGatewayAdapter.StarknetMessageConsumed(fromAddress, msgHash, payload);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            FELT-CHUNK CODEC (v1)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Encodes `payload` bytes into felts per the LATTICE FELT-CHUNK CONVENTION v1 — the wire format
    ///         the Cairo `l1_handler` must mirror: `felts[0] = payload.length` (byte count); `felts[1..]` =
    ///         consecutive 31-byte big-endian chunks of the payload, the last chunk right-padded with zeros.
    /// @dev Each chunk is `< 2**248 < FIELD_PRIME` by construction. An empty payload encodes to `[0]`.
    ///      Exact inverse of {decodeFelts}.
    function encodeFelts(bytes memory payload) internal pure returns (uint256[] memory felts) {
        uint256 len = payload.length;
        unchecked {
            uint256 chunks = (len + 30) / 31;
            felts = new uint256[](chunks + 1);
            felts[0] = len;
            for (uint256 i; i < chunks; ++i) {
                uint256 start = i * 31;
                uint256 end = start + 31;
                if (end > len) end = len;
                uint256 chunk;
                for (uint256 j = start; j < end; ++j) {
                    chunk = (chunk << 8) | uint8(payload[j]);
                }
                // Right-pad the (possibly partial) last chunk into the 31-byte big-endian frame.
                chunk <<= 8 * (31 - (end - start));
                felts[i + 1] = chunk;
            }
        }
    }

    /// @notice Decodes a LATTICE FELT-CHUNK CONVENTION v1 felt array back into the original bytes payload.
    /// @dev STRICT exact inverse of {encodeFelts}: reverts {StarknetMalformedFeltPayload} on a missing/wrong
    ///      length prefix, a chunk `>= 2**248`, or non-zero padding bits in the final chunk — so
    ///      `decodeFelts(encodeFelts(x)) == x` and every accepted felt array is canonical.
    function decodeFelts(uint256[] memory felts) internal pure returns (bytes memory payload) {
        uint256 n = felts.length;
        if (n == 0) revert IStarknetGatewayAdapter.StarknetMalformedFeltPayload();
        uint256 len = felts[0];
        unchecked {
            uint256 chunks = (len + 30) / 31;
            if (n != chunks + 1) revert IStarknetGatewayAdapter.StarknetMalformedFeltPayload();
            payload = new bytes(len);
            for (uint256 i; i < chunks; ++i) {
                uint256 chunk = felts[i + 1];
                if (chunk >= CHUNK_BOUND) revert IStarknetGatewayAdapter.StarknetMalformedFeltPayload();
                uint256 start = i * 31;
                uint256 k = len - start;
                if (k > 31) k = 31;
                // Non-canonical padding (non-zero bits below the k data bytes) is rejected.
                if (chunk & ((1 << (8 * (31 - k))) - 1) != 0) {
                    revert IStarknetGatewayAdapter.StarknetMalformedFeltPayload();
                }
                for (uint256 j; j < k; ++j) {
                    payload[start + j] = bytes1(uint8(chunk >> (8 * (30 - j))));
                }
            }
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Parses the ERC-7930 `recipient` into a validated felt252 and fail-closed checks it targets THIS
    ///         adapter's Starknet chain, then resolves the registered `l1_handler` selector (send path only —
    ///         cancellation takes the send-time selector explicitly, see {startCancellation}).
    /// @dev Reverts {StarknetTargetNotRegistered} when no selector is registered for the target.
    function _parseAndCheckRecipient(StarknetGatewayAdapterStorage storage $, bytes calldata recipient)
        private
        view
        returns (uint256 toFelt, uint256 selector)
    {
        toFelt = _parseRecipientFelt($, recipient);
        selector = $._l1HandlerSelector[toFelt];
        if (selector == 0) revert IStarknetGatewayAdapter.StarknetTargetNotRegistered(toFelt);
    }

    /// @notice Parses the ERC-7930 `recipient` into a validated felt252 target on THIS adapter's Starknet chain.
    /// @dev Reverts {StarknetWrongChainType} on a non-starknet chainType, {StarknetChainReferenceMismatch} on a
    ///      foreign chain reference. Felt range/zero checks live in {NonEvmAddress.parseV1ToFelt252}.
    function _parseRecipientFelt(StarknetGatewayAdapterStorage storage $, bytes calldata recipient)
        private
        view
        returns (uint256 toFelt)
    {
        (bytes2 chainType, bytes memory chainReference, uint256 felt) = NonEvmAddress.parseV1ToFelt252(recipient);
        if (chainType != NonEvmAddress.STARKNET_CHAIN_TYPE) {
            revert IStarknetGatewayAdapter.StarknetWrongChainType(chainType);
        }
        if (keccak256(chainReference) != keccak256($._expectedChainReference)) {
            revert IStarknetGatewayAdapter.StarknetChainReferenceMismatch();
        }
        toFelt = felt;
    }

    /// @notice Requires `value` to be a valid non-zero felt252 (`0 < value < FIELD_PRIME`).
    function _checkFelt(uint256 value) private pure {
        if (value == 0 || value >= NonEvmAddress.FIELD_PRIME) {
            revert IStarknetGatewayAdapter.StarknetNotAFelt(value);
        }
    }
}
