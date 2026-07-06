// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IStarknetGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Starknet (https://github.com/starkware-libs/cairo-lang)
/// @notice Surface of the L1-side (Ethereum-only) Starknet L1 <-> L2 connector: fee-escrowed outbound
///         `sendMessage` toward an ERC-7930 Starknet (felt252) recipient, initiator-gated two-step
///         cancellation, and a permissionless keeper-driven inbound `consumeMessage` pull.
/// @dev DELIBERATELY BESPOKE, not an `IERC7786GatewaySource`: ERC-7786's `sendMessage` returns a `sendId` for a
///      symmetric receive-side dedup that does not exist here (the inbound path is a PULL-based consume against
///      a core-side COUNTER, not a pushed message with an id), ERC-7786 attributes cannot express the escrowed
///      non-refundable fee + the two-step cancellation lifecycle, and the Starknet wire payload is a felt252
///      array, not opaque bytes. It is never routed through OpenBridge / CrosschainLink.
///
///      WIRE FORMAT (Lattice felt-chunk convention v1 — the Cairo l1_handler must mirror it):
///      `felts[0] = payload byte count; felts[1..] = consecutive 31-byte big-endian chunks of the payload, the
///      last chunk right-padded with zeros`. Each chunk is `< 2**248 < FIELD_PRIME` by construction.
///
///      FEE WARNING: the L1 -> L2 message fee (`msg.value`) is escrowed by the Starknet core and NEVER
///      refunded — not even when the message is cancelled.
interface IStarknetGatewayAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when an L1 -> L2 message is sent to the Starknet core.
    /// @param initiator The L1 caller recorded as the only party allowed to cancel this message.
    /// @param toAddress The L2 target contract (felt252).
    /// @param selector  The registered `l1_handler` selector invoked on the target.
    /// @param msgHash   The core-computed message hash.
    /// @param nonce     The core-minted message nonce (needed for cancellation).
    /// @param fee       The escrowed, NON-REFUNDABLE message fee (wei).
    /// @param payload   The raw bytes payload (pre felt-chunk encoding).
    event StarknetMessageSent(
        address indexed initiator,
        uint256 indexed toAddress,
        uint256 selector,
        bytes32 msgHash,
        uint256 nonce,
        uint256 fee,
        bytes payload
    );

    /// @notice Emitted when a two-step cancellation is started for `msgHash` by its initiator.
    event StarknetCancellationStarted(address indexed initiator, bytes32 indexed msgHash, uint256 nonce);

    /// @notice Emitted when `msgHash` is cancelled by its initiator (the escrowed fee is NOT refunded).
    event StarknetMessageCancelled(address indexed initiator, bytes32 indexed msgHash, uint256 nonce);

    /// @notice Emitted when an L2 -> L1 message from `fromAddress` is consumed from the core.
    event StarknetMessageConsumed(uint256 indexed fromAddress, bytes32 msgHash, bytes payload);

    /// @notice Emitted when an L2 target's `l1_handler` selector is registered.
    event RegisteredL2Handler(uint256 indexed l2Target, uint256 selector);

    /// @notice Emitted when an L2 sender's trusted flag is set for the inbound consume path.
    event SetTrustedL2Sender(uint256 indexed fromAddress, bool trusted);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice The Starknet core address was zero at init.
    error StarknetZeroAddress();

    /// @notice The expected chain reference was empty at init.
    error StarknetEmptyChainReference();

    /// @notice The ERC-7930 recipient's chainType is not the starknet ChainType key (`0x0003`).
    error StarknetWrongChainType(bytes2 chainType);

    /// @notice The ERC-7930 recipient's chain reference does not match this adapter's configured Starknet
    ///         chain (e.g. `SN_GOERLI` recipient on an `SN_MAIN` adapter) — fail-closed.
    error StarknetChainReferenceMismatch();

    /// @notice No `l1_handler` selector is registered for the L2 target decoded from the recipient.
    error StarknetTargetNotRegistered(uint256 toAddress);

    /// @notice `sendMessage` was called with zero `msg.value` (the core requires a non-zero fee).
    error StarknetZeroFee();

    /// @notice The caller is not the recorded initiator of the message being cancelled.
    error StarknetNotInitiator(bytes32 msgHash, address caller);

    /// @notice The inbound L2 sender is not on the trusted-senders allow-list.
    error StarknetUntrustedSender(uint256 fromAddress);

    /// @notice An admin-supplied value is not a valid non-zero felt252 (`0 < value < FIELD_PRIME`).
    error StarknetNotAFelt(uint256 value);

    /// @notice A felt array does not follow the Lattice felt-chunk convention v1 (bad length prefix, chunk
    ///         `>= 2**248`, or non-zero padding in the final chunk).
    error StarknetMalformedFeltPayload();

    // -------------------------------------------------------------------------
    //                                  Reads
    // -------------------------------------------------------------------------

    /// @notice The Starknet core (`StarknetMessaging`) contract on this chain.
    function starknetCore() external view returns (address);

    /// @notice The ERC-7930 chain reference this adapter accepts (UTF-8 chain-id string, e.g. `SN_MAIN`).
    function expectedChainReference() external view returns (bytes memory);

    /// @notice The registered `l1_handler` selector for `l2Target` (0 = unregistered).
    function l1HandlerSelector(uint256 l2Target) external view returns (uint256);

    /// @notice Whether `fromAddress` is a trusted L2 sender for the inbound consume path.
    function isTrustedL2Sender(uint256 fromAddress) external view returns (bool);

    /// @notice The initiator recorded for an in-flight outbound message (address(0) = unknown/cancelled).
    function initiatorOf(bytes32 msgHash) external view returns (address);

    /// @notice Computes the Starknet selector (`starknet_keccak`) of an `l1_handler` entry-point `name`:
    ///         `uint256(keccak256(bytes(name))) & ((1 << 250) - 1)` (keccak256 masked to its low 250 bits).
    /// @dev Convenience for admins registering handlers — selectors CANNOT be derived from the ERC-7930
    ///      address, they are a property of the target contract's Cairo code.
    function starknetSelector(string calldata name) external pure returns (uint256);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Registers the `l1_handler` selector to invoke when sending to `l2Target`. Both values must be
    ///         non-zero felt252s. Admin only.
    function registerL2Handler(uint256 l2Target, uint256 selector) external;

    /// @notice Sets the trusted flag of the L2 sender `fromAddress` (a non-zero felt252) for the inbound
    ///         consume path. Admin only.
    function setTrustedL2Sender(uint256 fromAddress, bool trusted) external;

    // -------------------------------------------------------------------------
    //                                  Actions
    // -------------------------------------------------------------------------

    /// @notice Sends `payload` (felt-chunk encoded) to the ERC-7930 Starknet `recipient`'s registered
    ///         `l1_handler`, escrowing `msg.value` as the message fee.
    /// @dev The fee is escrowed by the Starknet core and NEVER refunded — cancellation included. The caller is
    ///      recorded as the message's initiator and is the only party able to cancel it.
    /// @param recipient The ERC-7930 interoperable recipient (starknet chainType + chain reference + felt252).
    /// @param payload   The raw bytes payload (encoded per the felt-chunk convention v1 on the wire).
    /// @return msgHash The core-computed message hash.
    /// @return nonce   The core-minted message nonce (keep it — cancellation needs it).
    function sendMessage(bytes calldata recipient, bytes calldata payload)
        external
        payable
        returns (bytes32 msgHash, uint256 nonce);

    /// @notice Starts the two-step cancellation of a previously sent message, re-derived from the ORIGINAL
    ///         `recipient`/`selector`/`payload`/`nonce`. Initiator only.
    /// @dev `selector` is the SEND-TIME `l1_handler` selector (emitted in {StarknetMessageSent}) — passed
    ///      explicitly and NOT re-read from the mutable handler registry, so an admin re-registering the
    ///      target's selector while the message is in flight cannot lock the initiator out of cancelling.
    ///      The core enforces a `messageCancellationDelay()` wait between this call and {cancel}.
    function startCancellation(bytes calldata recipient, uint256 selector, bytes calldata payload, uint256 nonce)
        external
        returns (bytes32 msgHash);

    /// @notice Completes the cancellation started by {startCancellation} (same arguments), at least
    ///         `messageCancellationDelay()` seconds later. Initiator only. The escrowed fee is NOT refunded.
    function cancel(bytes calldata recipient, uint256 selector, bytes calldata payload, uint256 nonce)
        external
        returns (bytes32 msgHash);

    /// @notice Permissionless keeper-driven pull: consumes an L2 -> L1 message from the trusted L2 sender
    ///         `fromAddress` addressed to this diamond, and emits it. Emit-only in v1.
    /// @dev The core is the real authenticator (it only consumes messages addressed to `msg.sender` — the
    ///      diamond — and reverts when the message counter is zero). Counter semantics: duplicates are N
    ///      DISTINCT consumes, not replays — consuming the same message twice requires the L2 to have SENT it
    ///      twice. NOT routed into CrosschainLink / OpenBridge.
    function consumeMessage(uint256 fromAddress, bytes calldata payload) external returns (bytes32 msgHash);
}
