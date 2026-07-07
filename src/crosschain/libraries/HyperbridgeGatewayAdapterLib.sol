// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {BridgeFungibleLib} from "@lattice/crosschain/libraries/BridgeFungibleLib.sol";
import {AdapterBaseLib} from "@lattice/defi/libraries/AdapterBaseLib.sol";
import {IHyperbridgeGatewayAdapter} from "@lattice/interfaces/crosschain/IHyperbridgeGatewayAdapter.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/IERC7786.sol";
import {
    DispatchPost,
    IIsmpDispatcher,
    IncomingPostRequest,
    PostRequest
} from "@lattice/interfaces/external/IIsmpDispatcher.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {Strings} from "@lattice/utils/libraries/Strings.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.HyperbridgeGatewayAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant HYPERBRIDGE_GATEWAY_ADAPTER_STORAGE_SLOT =
    0x51a6b52d433abb3ae06100272e5ee46754531b734f9cac910997924c61569700;

/// @dev ERC-165 map slot for `IERC7786GatewaySource` (`0x11967553`). SHARED by all gateway adapters —
///      `keccak256(abi.encode(bytes4(0x11967553), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC7786GATEWAYSOURCE_SLOT =
    0x3c75b8ea75c097979221eb9302e2f0f6009b4ffe0a7198db5dc29979e09ea0e3;

/// @dev 0x9c48e32e is `type(IHyperbridgeGatewayAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x9c48e32e), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IHYPERBRIDGEGATEWAYADAPTER_SLOT =
    0xb7ece225a1d7ee3cb3d032ac79e8edc4e7bc0b80a422071828120db87beadfcb;

/// @notice ERC-7201 namespaced storage for the Hyperbridge (ISMP) gateway adapter.
/// @custom:storage-location erc7201:lattice.storage.HyperbridgeGatewayAdapter
struct HyperbridgeGatewayAdapterStorage {
    /// @notice The Hyperbridge IsmpHost (OZ-style immutable → Diamond storage). APPEND-ONLY.
    address _host;
    /// @notice EVM chainId => ISMP state machine id (empty = unset). Admin-registered; for EVM chains DERIVED
    ///         as `bytes("EVM-" + chainId)`, never caller-supplied. APPEND-ONLY.
    mapping(uint256 chainId => bytes stateMachineId) _stateMachineIds;
    /// @notice `keccak256(stateMachineId)` => EVM chainId (0 = unset). Loud-duplicate reverse map + inbound
    ///         source resolution. APPEND-ONLY.
    mapping(bytes32 smHash => uint256 chainId) _chainIds;
    /// @notice Trusted remote ISMP module (counterpart adapter) per chainId (empty = unset; tunable).
    ///         APPEND-ONLY.
    mapping(uint256 chainId => bytes remoteModule) _trustedRemotes;
    /// @notice Per-destination dispatch timeout in seconds (0 = no explicit timeout — host default; tunable).
    ///         APPEND-ONLY.
    mapping(uint256 chainId => uint64 timeout) _destTimeout;
    /// @notice Monotonic outbound counter. The ISMP protocol nonce is HOST-side and unknowable pre-dispatch,
    ///         so each envelope carries this source-minted nonce, giving the suite-level
    ///         `sendId = keccak256(abi.encode(sourceChainId, nonce))` identity every sibling adapter uses.
    ///         APPEND-ONLY.
    uint256 _lastNonce;
    /// @notice Replay guard: per source chainId, the set of consumed (source, protocol-nonce) dedup keys.
    ///         APPEND-ONLY.
    mapping(uint256 chainId => mapping(bytes32 dedupKey => bool executed)) _executed;
}

/// @title HyperbridgeGatewayAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Hyperbridge (https://github.com/polytope-labs/ismp-solidity)
/// @notice Logic + ERC-7201 storage for the Hyperbridge (ISMP) ERC-7786 gateway adapter. `sendMessage` wraps
///         the ERC-7930 envelope with a source-minted nonce and dispatches a proof-verified POST request via
///         `IIsmpDispatcher.dispatch`, paying the per-byte protocol fee + optional relayer fee in the host's
///         ERC-20 `feeToken()` (CCTP-style pull/approve/reset hygiene — no `msg.value`); `onAccept` is the
///         host-gated delivery callback (source state machine + trusted module auth, (source, protocol-nonce)
///         dedup, ERC-7930 delivery); `onPostRequestTimeout` is the native timeout notification.
/// @dev Wire envelope = `abi.encode(senderInteropAddr, recipientInteropAddr, innerPayload, nonce)` (the suite
///      4-tuple). State machine ids are BYTES strings: for EVM chains the id is DERIVED as
///      `bytes("EVM-" + Strings.toString(chainId))` — upstream `StateMachine.evm` re-implemented here in one
///      line rather than vendoring StateMachine.sol; non-EVM ids (POLKADOT-/SUBSTRATE-) are admin-supplied
///      raw. REFUND-CRITICAL: `DispatchPost.payer` is ALWAYS the sending user (`msg.sender`), NEVER
///      `address(this)` — the host refunds timeout fees to the payer, and a diamond payer would strand them.
///      The host's `feeToken()` is read LIVE on every send/quote (the host can migrate it — caching would
///      charge/approve the wrong token). A native-token fee path (host-side uniswap swap of `msg.value`)
///      exists upstream but is DEFERRED — stray value reverts in v1 (issue #77 Q13).
library HyperbridgeGatewayAdapterLib {
    function hyperbridgeGatewayAdapterStorage() internal pure returns (HyperbridgeGatewayAdapterStorage storage $) {
        assembly {
            $.slot := HYPERBRIDGE_GATEWAY_ADAPTER_STORAGE_SLOT
        }
    }

    /// @notice Stores the IsmpHost (zero reverts {HyperbridgeZeroHost} — an unconfigured adapter must not
    ///         exist) and registers the gateway-source + adapter ERC-165 ids.
    function __HyperbridgeGatewayAdapter_init(address host_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        if (host_ == address(0)) revert IHyperbridgeGatewayAdapter.HyperbridgeZeroHost();
        hyperbridgeGatewayAdapterStorage()._host = host_;
        registerInterfaces();
    }

    /// @notice Writes `true` to the SHARED IERC7786GatewaySource ERC-165 map slot (0x11967553 → ...; same
    ///         slot the CCIP/LayerZero/Wormhole/Axelar/Hyperlane adapters register — a Diamond mounts at most
    ///         one gateway) and to the adapter's own IHyperbridgeGatewayAdapter map slot.
    function registerInterfaces() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC7786GATEWAYSOURCE_SLOT, true)
            sstore(ERC165_MAP_IHYPERBRIDGEGATEWAYADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function ismpHost() internal view returns (address) {
        return hyperbridgeGatewayAdapterStorage()._host;
    }

    /// @notice LIVE passthrough of the host's current ERC-20 fee token — deliberately never cached (the host
    ///         can migrate it, and a cached token would charge/approve the wrong asset).
    function hyperbridgeFeeToken() internal view returns (address) {
        return IIsmpDispatcher(hyperbridgeGatewayAdapterStorage()._host).feeToken();
    }

    function stateMachineIdOf(uint256 chainId) internal view returns (bytes memory) {
        return hyperbridgeGatewayAdapterStorage()._stateMachineIds[chainId];
    }

    function chainIdOfStateMachine(bytes calldata stateMachineId) internal view returns (uint256) {
        return hyperbridgeGatewayAdapterStorage()._chainIds[keccak256(stateMachineId)];
    }

    function hyperbridgeRemoteModuleOf(uint256 chainId) internal view returns (bytes memory) {
        return hyperbridgeGatewayAdapterStorage()._trustedRemotes[chainId];
    }

    function hyperbridgeDestTimeoutOf(uint256 chainId) internal view returns (uint64) {
        return hyperbridgeGatewayAdapterStorage()._destTimeout[chainId];
    }

    /// @notice No `sendMessage` attributes are supported by this adapter (the relayer fee rides the separate
    ///         typed {sendMessageWithFee} entrypoint, not an attribute).
    function supportsAttribute(bytes4) internal pure returns (bool) {
        return false;
    }

    /// @notice Quotes the TOTAL `feeToken` cost of a send: `perByteFee(dest) * body.length + relayerFee`,
    ///         where `body` is the exact wire envelope a real send would dispatch (SAME builder, with the NEXT
    ///         nonce — envelope length is sender/nonce-independent, so the quote matches the send-time
    ///         charge). The host's 32-byte minimum-body floor never binds: the envelope is always ≥ 4 ABI
    ///         words.
    function quoteDispatchFee(bytes calldata recipient, bytes calldata payload, uint256 relayerFee)
        internal
        view
        returns (uint256)
    {
        HyperbridgeGatewayAdapterStorage storage $ = hyperbridgeGatewayAdapterStorage();
        (, bytes memory stateMachineId,) = _resolveDestination($, recipient);
        bytes memory envelope = _buildEnvelope(recipient, payload, $._lastNonce + 1);
        return IIsmpDispatcher($._host).perByteFee(stateMachineId) * envelope.length + relayerFee;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the EVM chainId ⇄ state machine equivalence for `chainId`, deriving the id INTERNALLY
    ///         as {evmStateMachineId} — never caller-supplied (fail-closed: a typoed id cannot misroute).
    ///         FAIL-LOUD identity admin (both directions, via the keccak reverse map). Admin only.
    function registerStateMachine(uint256 chainId) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _registerStateMachine(chainId, evmStateMachineId(chainId));
    }

    /// @notice Registers a RAW (non-EVM: POLKADOT-/SUBSTRATE-/KUSAMA-) state machine id under a LOCAL routing
    ///         `chainId` handle, with empty-id rejection and the same fail-loud both-direction rules. Admin
    ///         only.
    function registerStateMachineRaw(uint256 chainId, bytes calldata stateMachineId) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (stateMachineId.length == 0) revert IHyperbridgeGatewayAdapter.HyperbridgeEmptyStateMachineId();
        _registerStateMachine(chainId, stateMachineId);
    }

    /// @notice Sets the trusted remote ISMP module (counterpart adapter) for a chain. TUNABLE (updatable), but
    ///         never empty — clearing a corridor is not supported in v1. Admin only.
    function registerRemoteModule(uint256 chainId, bytes calldata module) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (module.length == 0) revert IHyperbridgeGatewayAdapter.HyperbridgeEmptyRemoteModule();
        hyperbridgeGatewayAdapterStorage()._trustedRemotes[chainId] = module;
        emit IHyperbridgeGatewayAdapter.RegisteredRemoteModule(chainId, module);
    }

    /// @notice Configures a destination's dispatch timeout in seconds. TUNABLE; 0 = no explicit timeout (the
    ///         host's default handling). Admin only.
    function configureDestinationTimeout(uint256 chainId, uint64 timeout) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        hyperbridgeGatewayAdapterStorage()._destTimeout[chainId] = timeout;
        emit IHyperbridgeGatewayAdapter.ConfiguredDestinationTimeout(chainId, timeout);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   SEND
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice ERC-7786 source. Delegates to {sendMessageWithFee} with `relayerFee = 0` (unfunded/self-relay,
    ///         valid in ISMP — anyone may still relay the proof permissionlessly).
    /// @dev No attributes are supported — any attribute reverts {UnsupportedAttribute}. The interface forces
    ///      `payable`, but the native-token fee path is DEFERRED (issue #77 Q13) — stray value reverts
    ///      {HyperbridgeUnexpectedValue} instead of being trapped in the Diamond.
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        internal
        returns (bytes32)
    {
        if (attributes.length != 0) revert IERC7786GatewaySource.UnsupportedAttribute(bytes4(attributes[0]));
        if (msg.value != 0) revert IHyperbridgeGatewayAdapter.HyperbridgeUnexpectedValue(msg.value);
        return sendMessageWithFee(recipient, payload, 0);
    }

    /// @notice Sends `payload` to the ERC-7930 `recipient`, funding an ISMP relayer fee of `relayerFee` on top
    ///         of the per-byte protocol fee — both charged in the host's LIVE `feeToken()` and pulled from the
    ///         caller with CCTP-style hygiene: pull exactly `total`, force-approve the host for exactly
    ///         `total`, dispatch, reset the allowance to 0, then delta-sweep any leftover back to the caller
    ///         (defensive — the host should pull exactly `total`).
    /// @dev The envelope carries a source-owned monotonic nonce (`++$._lastNonce`) so the delivery id is
    ///      globally unique per (source, nonce) — the ISMP protocol nonce is host-side and unknowable
    ///      pre-dispatch, so the envelope nonce keeps the suite-level identity every sibling adapter uses.
    ///      REFUND-CRITICAL: `DispatchPost.payer = msg.sender` (the USER) — a diamond payer would strand
    ///      host-side timeout fee refunds. Returns `sendId = keccak256(abi.encode(block.chainid, nonce))`; the
    ///      ISMP `commitment` is surfaced via {HyperbridgeMessageDispatched}.
    function sendMessageWithFee(bytes calldata recipient, bytes calldata payload, uint256 relayerFee)
        internal
        returns (bytes32 sendId)
    {
        HyperbridgeGatewayAdapterStorage storage $ = hyperbridgeGatewayAdapterStorage();
        uint256 nonce = ++$._lastNonce;
        sendId = keccak256(abi.encode(block.chainid, nonce));

        // Dispatch is a separate helper so the routing locals free before the emit (non-via-IR stack budget).
        _dispatch($, recipient, payload, relayerFee, nonce, sendId);

        emit IERC7786GatewaySource.MessageSent(
            sendId, InteroperableAddress.formatEvmV1(block.chainid, msg.sender), recipient, payload, 0, new bytes[](0)
        );
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  RECEIVE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Host delivery callback: DUAL AUTH — `msg.sender` must be the IsmpHost AND `request.from` (the
    ///         origin module) must byte-equal the non-empty trusted remote registered for the source state
    ///         machine's chain (fail-closed on an unregistered source or an unset remote). De-dups per
    ///         (chainId, `keccak256(abi.encode(source, protocolNonce))`), marking BEFORE the external delivery
    ///         (checks-effects-interactions), then delivers to the ERC-7930 recipient encoded in the envelope.
    /// @dev The dedup key uses the ISMP PROTOCOL nonce — host-side unique per source — as suite-convention
    ///      defense-in-depth over the host's own commitment uniqueness (the host never redelivers a settled
    ///      commitment; this guard makes the adapter safe even against a buggy host re-invocation).
    ///      `nonReentrant`: delivery calls an arbitrary recipient.
    function onAccept(IncomingPostRequest calldata incoming) internal {
        ReentrancyGuardLib.nonReentrantBefore();
        HyperbridgeGatewayAdapterStorage storage $ = hyperbridgeGatewayAdapterStorage();
        if (msg.sender != $._host) revert IHyperbridgeGatewayAdapter.HyperbridgeNotHost(msg.sender);

        PostRequest calldata request = incoming.request;
        uint256 chainId = $._chainIds[keccak256(request.source)];
        if (chainId == 0) revert IHyperbridgeGatewayAdapter.HyperbridgeUnknownSource(request.source);
        {
            bytes memory trusted = $._trustedRemotes[chainId];
            // Reject an unset remote (empty bytes) explicitly, so a source registered before its remote can
            // never satisfy auth against an empty `from` delivery.
            if (trusted.length == 0 || keccak256(request.from) != keccak256(trusted)) {
                revert IHyperbridgeGatewayAdapter.HyperbridgeUntrustedModule(request.from);
            }
        }

        // CEI replay guard on the host-side-unique (source, protocol nonce) pair; marked BEFORE delivery.
        bytes32 dedupKey = keccak256(abi.encode(request.source, request.nonce));
        if ($._executed[chainId][dedupKey]) {
            revert IHyperbridgeGatewayAdapter.HyperbridgeMessageAlreadyExecuted(chainId, dedupKey);
        }
        $._executed[chainId][dedupKey] = true;

        (bytes memory senderInterop, bytes memory recipient, bytes memory inner, uint256 nonce) =
            abi.decode(request.body, (bytes, bytes, bytes, uint256));
        (uint256 recipientChainId, address target) = InteroperableAddress.parseEvmV1(recipient);
        // Defense-in-depth: the source routes by the recipient's chainId, so a well-behaved remote only ever
        // delivers messages whose recipient targets THIS chain; a rogue/buggy trusted remote cannot misdirect.
        if (recipientChainId != block.chainid) {
            revert IHyperbridgeGatewayAdapter.HyperbridgeWrongDestinationChain(recipientChainId);
        }
        if (
            IERC7786Recipient(target).receiveMessage(keccak256(abi.encode(chainId, nonce)), senderInterop, inner)
                != IERC7786Recipient.receiveMessage.selector
        ) {
            revert IHyperbridgeGatewayAdapter.HyperbridgeRecipientExecutionFailed();
        }
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Host timeout callback for a request WE dispatched: decodes the envelope and emits
    ///         {HyperbridgeRequestTimedOut}. EMIT-ONLY in v1 — the fee refund itself is HOST-SIDE to
    ///         `DispatchPost.payer` (the original sending user); this hook is the notification surface an
    ///         application layer keys compensating actions off (issue #77 Q8).
    /// @dev A timeout fires on the SOURCE chain for our own dispatch, so `request.source` is OUR state machine
    ///      and `request.from` is OUR module — neither is attacker-controlled once `msg.sender == host` holds,
    ///      which is the REAL auth here (the host only ever times out commitments it stored at dispatch).
    ///      `sendId = keccak256(abi.encode(block.chainid, envelopeNonce))` reconstructs the original send id
    ///      because `block.chainid` equals the send-time source chainId. `nonReentrant` for symmetry with
    ///      {onAccept} (the emit path makes no external calls, but the guard keeps the hook surface uniform).
    function onPostRequestTimeout(PostRequest calldata request) internal {
        ReentrancyGuardLib.nonReentrantBefore();
        if (msg.sender != hyperbridgeGatewayAdapterStorage()._host) {
            revert IHyperbridgeGatewayAdapter.HyperbridgeNotHost(msg.sender);
        }
        (bytes memory senderInterop,, bytes memory inner, uint256 nonce) =
            abi.decode(request.body, (bytes, bytes, bytes, uint256));
        emit IHyperbridgeGatewayAdapter.HyperbridgeRequestTimedOut(
            keccak256(abi.encode(block.chainid, nonce)), senderInterop, inner
        );
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice The four `IIsmpModule` hooks the adapter never uses (`onPostResponse`, `onGetResponse`,
    ///         `onPostResponseTimeout`, `onGetTimeout`) revert unconditionally — the adapter dispatches
    ///         neither GETs nor responses, so silently accepting them would be a spoofable no-op surface.
    function unsupportedHook() internal pure {
        revert IHyperbridgeGatewayAdapter.HyperbridgeUnsupportedHook();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The canonical ISMP state machine id of an EVM chain: `bytes("EVM-" + decimal chainId)`.
    /// @dev One-line re-implementation of upstream `StateMachine.evm` (ismp-solidity `StateMachine.sol`) with
    ///      the repo's vendored {Strings} — deliberately not vendoring the whole StateMachine lib.
    function evmStateMachineId(uint256 chainId) internal pure returns (bytes memory) {
        return bytes(string.concat("EVM-", Strings.toString(chainId)));
    }

    /// @notice Registers `chainId` ⇄ `stateMachineId` in BOTH directions. Reverts {HyperbridgeZeroChainId} on
    ///         chainId 0 (0 is the reverse-map unset sentinel) and fails LOUD
    ///         ({HyperbridgeStateMachineAlreadyRegistered}) when either direction is already mapped —
    ///         identities are never remapped.
    function _registerStateMachine(uint256 chainId, bytes memory stateMachineId) private {
        if (chainId == 0) revert IHyperbridgeGatewayAdapter.HyperbridgeZeroChainId();
        HyperbridgeGatewayAdapterStorage storage $ = hyperbridgeGatewayAdapterStorage();
        if ($._stateMachineIds[chainId].length != 0 || $._chainIds[keccak256(stateMachineId)] != 0) {
            revert IHyperbridgeGatewayAdapter.HyperbridgeStateMachineAlreadyRegistered(chainId, stateMachineId);
        }
        $._stateMachineIds[chainId] = stateMachineId;
        $._chainIds[keccak256(stateMachineId)] = chainId;
        emit IHyperbridgeGatewayAdapter.RegisteredStateMachine(chainId, stateMachineId);
    }

    /// @notice Resolves `recipient`'s chain into (chainId, state machine id, trusted remote module).
    /// @dev Reverts {HyperbridgeUnknownDestinationChain} if the state machine id or remote module is unset —
    ///      fail-closed, mirroring the Hyperlane `_resolveDestination`. The eip-155 recipient parse is the
    ///      cross-check: routing keys off the REGISTERED map for the recipient's own chainId, never off
    ///      caller-supplied ids.
    function _resolveDestination(HyperbridgeGatewayAdapterStorage storage $, bytes calldata recipient)
        private
        view
        returns (uint256 chainId, bytes memory stateMachineId, bytes memory module)
    {
        (chainId,) = InteroperableAddress.parseEvmV1Calldata(recipient);
        stateMachineId = $._stateMachineIds[chainId];
        module = $._trustedRemotes[chainId];
        if (stateMachineId.length == 0 || module.length == 0) {
            revert IHyperbridgeGatewayAdapter.HyperbridgeUnknownDestinationChain(chainId);
        }
    }

    /// @notice Resolves the destination, builds the {DispatchPost} (payer = the USER — REFUND-CRITICAL:
    ///         host-side timeout fee refunds go to the payer, and a diamond payer would strand them), runs the
    ///         fee-hygiene dispatch, and emits {HyperbridgeMessageDispatched}.
    function _dispatch(
        HyperbridgeGatewayAdapterStorage storage $,
        bytes calldata recipient,
        bytes calldata payload,
        uint256 relayerFee,
        uint256 nonce,
        bytes32 sendId
    ) private {
        (uint256 destChainId, bytes memory stateMachineId, bytes memory module) = _resolveDestination($, recipient);
        bytes32 commitment = _pullAndDispatch(
            $._host,
            DispatchPost({
                dest: stateMachineId,
                to: module,
                body: _buildEnvelope(recipient, payload, nonce),
                timeout: $._destTimeout[destChainId],
                fee: relayerFee,
                payer: msg.sender // REFUND-CRITICAL: the USER — host-side timeout refunds go to the payer.
            })
        );
        emit IHyperbridgeGatewayAdapter.HyperbridgeMessageDispatched(sendId, commitment, destChainId);
    }

    /// @notice The suite 4-tuple wire envelope: `abi.encode(sender7930, recipient7930, payload, nonce)`.
    ///         Shared by {sendMessageWithFee} and {quoteDispatchFee} so the quoted body IS the dispatched
    ///         body.
    function _buildEnvelope(bytes calldata recipient, bytes calldata payload, uint256 nonce)
        private
        view
        returns (bytes memory)
    {
        return abi.encode(InteroperableAddress.formatEvmV1(block.chainid, msg.sender), recipient, payload, nonce);
    }

    /// @notice CCTP-style ERC-20 fee hygiene around the ISMP dispatch: read the LIVE `feeToken`, pull exactly
    ///         `total = perByteFee(dest) * body.length + relayerFee` from the caller, force-approve the host
    ///         for exactly `total`, dispatch, reset the allowance to 0, then delta-sweep any leftover
    ///         `feeToken` back to the caller (defensive — the host should pull exactly `total`; a pre-existing
    ///         Diamond balance is never swept because only the balance DELTA is).
    function _pullAndDispatch(address host_, DispatchPost memory post) private returns (bytes32 commitment) {
        address feeToken_ = IIsmpDispatcher(host_).feeToken();
        uint256 total = IIsmpDispatcher(host_).perByteFee(post.dest) * post.body.length + post.fee;

        uint256 balanceBefore = AdapterBaseLib.balanceOfSelf(feeToken_);
        BridgeFungibleLib.pullExact(feeToken_, msg.sender, total);
        AdapterBaseLib.forceApprove(feeToken_, host_, total);
        commitment = IIsmpDispatcher(host_).dispatch(post);
        AdapterBaseLib.forceApprove(feeToken_, host_, 0);

        uint256 leftover = AdapterBaseLib.balanceOfSelf(feeToken_) - balanceBefore;
        if (leftover != 0) BridgeFungibleLib.safeTransfer(feeToken_, msg.sender, leftover);
    }
}
