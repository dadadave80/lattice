// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IHyperbridgeGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Hyperbridge (https://github.com/polytope-labs/ismp-solidity)
/// @notice Admin/read surface of the Hyperbridge (ISMP) ERC-7786 gateway adapter. The standard source-gateway
///         ABI (`sendMessage`/`supportsAttribute`) is on `IERC7786GatewaySource`; the inbound callbacks are
///         the host-invoked `IIsmpModule` hooks (`onAccept` for delivery, `onPostRequestTimeout` for the
///         native timeout notification). Hyperbridge is PROOF-VERIFIED interop — consensus + state proofs
///         aggregated on a Polkadot-secured coprocessor, delivered by permissionless proof-carrying relayers;
///         NO attestation committee.
/// @dev Hyperbridge routes by BYTES state machine ids (e.g. `bytes("EVM-8453")`, `bytes("POLKADOT-3367")`).
///      For EVM destinations the id is DERIVED from the chainId (never caller-supplied — fail-closed);
///      non-EVM ids go through {registerStateMachineRaw}. FEES are charged in the host's ERC-20
///      `feeToken()` (read LIVE at send time — the host can migrate it, so it is never cached):
///      `perByteFee(dest) * body.length` protocol fee plus an optional caller-funded relayer fee
///      ({sendMessageWithFee}; the plain `sendMessage` uses relayerFee 0 = unfunded/self-relay, valid in
///      ISMP). The dispatch `payer` is ALWAYS the sending user — the host refunds timeout fees to the payer,
///      and a diamond payer would strand them. A native-token fee path (host-side uniswap swap of msg.value)
///      exists upstream but is DEFERRED — the adapter rejects stray value in v1 (issue #77 Q13).
interface IHyperbridgeGatewayAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when an EVM chainId ⇄ state machine id equivalence is registered (both directions,
    ///         identity — never remapped).
    event RegisteredStateMachine(uint256 indexed chainId, bytes stateMachineId);

    /// @notice Emitted when the trusted remote ISMP module (counterpart adapter) for a chain is set (tunable).
    event RegisteredRemoteModule(uint256 indexed chainId, bytes module);

    /// @notice Emitted when a destination's dispatch timeout is configured (tunable; 0 = no explicit timeout —
    ///         the host's default handling).
    event ConfiguredDestinationTimeout(uint256 indexed chainId, uint64 timeout);

    /// @notice Emitted on every outbound dispatch, binding the suite-level ERC-7786 `sendId` to the ISMP
    ///         request `commitment` minted by the host.
    event HyperbridgeMessageDispatched(bytes32 indexed sendId, bytes32 indexed commitment, uint256 destChainId);

    /// @notice Emitted when the host notifies the adapter that a request WE dispatched timed out
    ///         (`onPostRequestTimeout`). EMIT-ONLY in v1: the fee refund itself is HOST-SIDE to
    ///         `DispatchPost.payer` (the original sending user); this event is the notification surface an
    ///         application layer can key compensating actions off (issue #77 Q8).
    /// @param sendId  The original suite-level sendId (`keccak256(abi.encode(block.chainid, envelopeNonce))` —
    ///                a timeout fires on the SOURCE chain, so `block.chainid` here equals the send-time one).
    /// @param sender  The ERC-7930 interoperable address of the original sender (decoded from the envelope).
    /// @param payload The original inner payload (decoded from the envelope).
    event HyperbridgeRequestTimedOut(bytes32 indexed sendId, bytes sender, bytes payload);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice The IsmpHost wired at init was the zero address.
    error HyperbridgeZeroHost();

    /// @notice The chainId being registered was 0 (0 is the unset sentinel of the reverse map).
    error HyperbridgeZeroChainId();

    /// @notice The raw state machine id being registered was empty bytes.
    error HyperbridgeEmptyStateMachineId();

    /// @notice A state machine equivalence is already registered for this chainId or id (fail-loud, BOTH
    ///         directions — identities are never remapped).
    error HyperbridgeStateMachineAlreadyRegistered(uint256 chainId, bytes stateMachineId);

    /// @notice The trusted remote module being registered was empty bytes (empty is the unset sentinel).
    error HyperbridgeEmptyRemoteModule();

    /// @notice The destination chain has no state machine id and/or no trusted remote module registered.
    error HyperbridgeUnknownDestinationChain(uint256 chainId);

    /// @notice Native value was supplied — the native-token fee path (host-side uniswap swap) is DEFERRED;
    ///         fees are charged in the host's ERC-20 `feeToken()` only in v1 (issue #77 Q13).
    error HyperbridgeUnexpectedValue(uint256 value);

    /// @notice The inbound callback was not invoked by the configured IsmpHost.
    error HyperbridgeNotHost(address caller);

    /// @notice The inbound request's source state machine is not registered (fail-closed).
    error HyperbridgeUnknownSource(bytes source);

    /// @notice The inbound request's origin module is not the trusted remote registered for its source chain
    ///         (or no remote is registered — an empty registered remote never matches).
    error HyperbridgeUntrustedModule(bytes from);

    /// @notice The inbound (source, protocol-nonce) pair was already delivered (replay).
    error HyperbridgeMessageAlreadyExecuted(uint256 chainId, bytes32 dedupKey);

    /// @notice The recipient's `receiveMessage` did not return the ERC-7786 magic value.
    error HyperbridgeRecipientExecutionFailed();

    /// @notice The inbound message's ERC-7930 recipient targets a different chain than this one
    ///         (defense-in-depth against a rogue/misconfigured trusted remote misdirecting delivery).
    error HyperbridgeWrongDestinationChain(uint256 chainId);

    /// @notice An `IIsmpModule` hook the adapter never uses was invoked (`onPostResponse`, `onGetResponse`,
    ///         `onPostResponseTimeout`, `onGetTimeout`) — the adapter dispatches neither GETs nor responses,
    ///         so silently accepting these would be a spoofable no-op surface.
    error HyperbridgeUnsupportedHook();

    // -------------------------------------------------------------------------
    //                                  Reads
    // -------------------------------------------------------------------------

    /// @notice The Hyperbridge IsmpHost the adapter dispatches to and accepts module callbacks from.
    function ismpHost() external view returns (address);

    /// @notice The host's CURRENT ERC-20 fee token (live passthrough of `IIsmpDispatcher.feeToken()` — never
    ///         cached; the host can migrate it).
    function hyperbridgeFeeToken() external view returns (address);

    /// @notice The state machine id registered for `chainId` (empty = unset).
    function stateMachineIdOf(uint256 chainId) external view returns (bytes memory);

    /// @notice The EVM chainId registered for the state machine id `stateMachineId` (0 = unset).
    function chainIdOfStateMachine(bytes calldata stateMachineId) external view returns (uint256);

    /// @notice The trusted remote ISMP module (counterpart adapter) registered for `chainId` (empty = unset).
    function hyperbridgeRemoteModuleOf(uint256 chainId) external view returns (bytes memory);

    /// @notice The configured dispatch timeout (seconds) for `chainId` (0 = no explicit timeout — the host's
    ///         default handling).
    function hyperbridgeDestTimeoutOf(uint256 chainId) external view returns (uint64);

    /// @notice Quotes the TOTAL `feeToken` cost of sending `payload` to `recipient` (ERC-7930) with
    ///         `relayerFee`: `perByteFee(destStateMachineId) * body.length + relayerFee`, where `body` is the
    ///         exact wire envelope a real send would dispatch (same builder — the envelope length is
    ///         sender/nonce-independent, so the quote matches the send-time charge).
    function quoteDispatchFee(bytes calldata recipient, bytes calldata payload, uint256 relayerFee)
        external
        view
        returns (uint256);

    // -------------------------------------------------------------------------
    //                                   Send
    // -------------------------------------------------------------------------

    /// @notice ERC-7786 send with an explicit ISMP relayer fee (charged in the host's `feeToken` on top of the
    ///         per-byte protocol fee; both pulled from the caller). The relayer fee lives OUTSIDE the
    ///         `IERC7786GatewaySource` ABI — same pattern as the LZ/Hyperlane fee-outside-the-ABI precedent —
    ///         and the plain `sendMessage` delegates here with `relayerFee = 0` (unfunded/self-relay, valid in
    ///         ISMP).
    /// @return sendId The suite-level `keccak256(abi.encode(block.chainid, envelopeNonce))` id.
    function sendMessageWithFee(bytes calldata recipient, bytes calldata payload, uint256 relayerFee)
        external
        returns (bytes32 sendId);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Registers the EVM chainId ⇄ state machine equivalence for `chainId`, deriving the id
    ///         INTERNALLY as the canonical `bytes("EVM-" + chainId)` — never caller-supplied (fail-closed).
    ///         FAIL-LOUD identity admin: an already-mapped chainId OR id reverts (both directions, via the
    ///         keccak reverse map) — identities are never remapped. Admin only.
    function registerStateMachine(uint256 chainId) external;

    /// @notice Registers a RAW (non-EVM) state machine id — POLKADOT/SUBSTRATE/KUSAMA destinations — mapped to
    ///         a local routing `chainId` handle. Same fail-loud both-direction rules as
    ///         {registerStateMachine}; empty ids and chainId 0 are rejected. The `chainId` is a LOCAL routing
    ///         key (it appears in the ERC-7930 recipient), so the admin must pick one that collides with no
    ///         real EVM chainId. Admin only.
    function registerStateMachineRaw(uint256 chainId, bytes calldata stateMachineId) external;

    /// @notice Sets the trusted remote ISMP module (counterpart adapter) for a chain. TUNABLE (updatable), but
    ///         never empty — clearing a corridor is not supported in v1. Admin only.
    function registerRemoteModule(uint256 chainId, bytes calldata module) external;

    /// @notice Configures a destination's dispatch timeout in seconds. TUNABLE; 0 = no explicit timeout (the
    ///         host's default handling). Admin only.
    function configureDestinationTimeout(uint256 chainId, uint64 timeout) external;
}
