// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IStargateBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Stargate (https://github.com/stargate-protocol/stargate-v2)
/// @notice Read / admin / action surface of the Stargate v2 POOLED-LIQUIDITY token-bridge adapter — the third
///         token rail beside CCTP (burn/mint) and Across (intent): `sendToken` pulls the token from the caller
///         and deposits it into the LOCAL Stargate pool, which debits shared unified liquidity so the
///         DESTINATION pool releases the token to the recipient. OUTBOUND-ONLY for plain transfers: the
///         destination-side receiver is Stargate's own pool (the LayerZero OApp), NOT a Lattice facet — there
///         is no Lattice inbound surface, no `receiveId`, no source attribution, and this is never routed
///         through OpenBridge. `composeMsg`/`lzCompose` hooks and bus mode are DEFERRED (see {sendToken}).
/// @dev Stargate rides LayerZero: destinations are keyed by the LayerZero `uint32` eid (admin-registered
///      bidirectional chainId ⇄ eid map, never inferred), and `msg.value` is the LayerZero messaging fee
///      EXCLUSIVELY — ERC-20 pools only in v1. Native-ETH pools (`StargatePoolNative`, where `msg.value` mixes
///      fee + send amount) are DEFERRED and MUST NOT be registered. Per-token pools are admin-registered
///      identities (register once, no re-pointing in v1) with a fail-closed `pool.token()` cross-check.
interface IStargateBridgeAdapter {
    // -------------------------------------------------------------------------
    //                                  Structs
    // -------------------------------------------------------------------------

    /// @notice Caller-supplied parameters of a Stargate `sendToken` (struct avoids stack-too-deep).
    struct SendTokenParams {
        /// @notice ERC-7930 interoperable address of the destination recipient (20-byte EVM or up-to-32-byte
        ///         non-EVM address field; down-converted to a right-aligned `bytes32`).
        bytes recipient;
        /// @notice The LOCAL ERC-20 sent through its registered Stargate pool.
        address token;
        /// @notice Amount of `token` (local decimals) pulled from the caller. The pool may debit LESS
        ///         (shared-decimal dust truncation) — the un-debited remainder is swept back to the caller.
        uint256 amountLD;
        /// @notice MANDATORY slippage floor (local decimals) on the destination-credited amount. Stargate
        ///         pools charge fees, so output < input; 0 would mean unlimited slippage and is rejected.
        uint256 minAmountLD;
        /// @notice EVM chainId of the destination chain (resolved to the registered LayerZero eid and
        ///         cross-checked against the ERC-7930 recipient's chain reference for eip-155 recipients).
        uint256 destinationChainId;
    }

    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when an EVM chainId ↔ LayerZero eid equivalence is registered (identity; fail-loud).
    event RegisteredEid(uint256 indexed chainId, uint32 eid);

    /// @notice Emitted when a token's Stargate pool is registered (identity; register once).
    event RegisteredPool(address indexed token, address indexed pool);

    /// @notice Emitted when a Stargate send is dispatched. `amountSentLD` is what the pool ACTUALLY debited
    ///         (may be less than the requested amount — dust already swept back to the sender);
    ///         `amountReceivedLD` what the destination credits after pool fees.
    event StargateTokenSent(
        address indexed sender,
        address indexed token,
        uint256 indexed destinationChainId,
        bytes32 guid,
        uint256 amountSentLD,
        uint256 amountReceivedLD,
        bytes32 recipient
    );

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice A required address argument (`token` or `pool` in {registerPool}) was the zero address.
    error StargateZeroAddress();

    /// @notice The chainId being registered was 0 (0 is the unset sentinel of the eid ⇒ chainId map).
    error StargateZeroChainId();

    /// @notice The eid being registered was 0 (0 is the unset sentinel of the chainId ⇒ eid map).
    error StargateZeroEid();

    /// @notice An eid equivalence is already registered for this chainId or eid (fail-loud, both maps —
    ///         identities are never remapped).
    error StargateEidAlreadyRegistered(uint256 chainId, uint32 eid);

    /// @notice The token already has a registered pool (identity — a pool upgrade cannot re-point a token
    ///         entry in v1; deliberate YAGNI).
    error StargateTokenAlreadyRegistered(address token);

    /// @notice FAIL-CLOSED registration cross-check: `pool.token()` does not match the token being registered
    ///         — a mis-registered pool would burn user approvals against the wrong asset.
    error StargatePoolTokenMismatch(address expected, address actual);

    /// @notice The token has no registered Stargate pool.
    error StargateTokenNotRegistered(address token);

    /// @notice The destination chain has no registered LayerZero eid.
    error StargateUnknownDestinationChain(uint256 chainId);

    /// @notice The send targeted this chain (`destinationChainId == block.chainid`).
    error StargateSameChain(uint256 chainId);

    /// @notice The send `amountLD` was zero.
    error StargateZeroAmount();

    /// @notice The send `minAmountLD` was zero (the mandatory slippage floor — pools charge fees, so 0 would
    ///         mean unlimited slippage).
    error StargateZeroMinAmount();

    /// @notice The ERC-7930 recipient declares an eip-155 chain that differs from `destinationChainId`.
    error StargateDestinationMismatch(uint256 declaredChainId, uint256 givenChainId);

    /// @notice The chain reference decoded from the ERC-7930 recipient does not fit in a uint256.
    error StargateChainReferenceTooLong(uint256 length);

    /// @notice `msg.value` was below the quoted LayerZero native fee (precheck, before any funds move).
    error StargateInsufficientFee(uint256 required, uint256 provided);

    // -------------------------------------------------------------------------
    //                                  Reads
    // -------------------------------------------------------------------------

    /// @notice The LayerZero eid registered for `chainId` (0 = unset).
    function stargateEidOf(uint256 chainId) external view returns (uint32);

    /// @notice The EVM chainId registered for `eid` (0 = unset).
    function stargateChainIdOf(uint32 eid) external view returns (uint256);

    /// @notice The Stargate pool registered for `token` (0 = unset).
    function poolOf(address token) external view returns (address);

    /// @notice Quotes the LayerZero native fee of a send, building the IDENTICAL `SendParam` the send path
    ///         dispatches (same internal builder — quote/send can never drift).
    function quoteSendFee(SendTokenParams calldata p) external view returns (uint256 nativeFee);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Registers an EVM chainId ↔ LayerZero eid equivalence (both directions, fail-loud — identities
    ///         are never remapped; zero chainId/eid rejected). Admin only.
    /// @dev Stargate rides LayerZero, so the eid here equals the LayerZero adapter's eid for the same chain —
    ///      recorded in this adapter's OWN map (adapters never share hot-path storage).
    function registerStargateEid(uint256 chainId, uint32 eid) external;

    /// @notice Registers `token`'s Stargate pool (identity — register once; {StargateTokenAlreadyRegistered}
    ///         on a duplicate). FAIL-CLOSED: reverts {StargatePoolTokenMismatch} unless `pool.token() ==
    ///         token`. Admin only.
    /// @dev ERC-20 pools only in v1 — never register a `StargatePoolNative` (its `token()` is address(0), so
    ///      the zero-token guard rejects it structurally). A pool upgrade cannot re-point an existing token
    ///      entry in v1 (deliberate YAGNI): ship a new adapter config instead.
    function registerPool(address token, address pool) external;

    // -------------------------------------------------------------------------
    //                                  Actions
    // -------------------------------------------------------------------------

    /// @notice Sends `p.amountLD` of `p.token` (pulled from `msg.sender`) through its registered Stargate
    ///         pool toward the ERC-7930 `p.recipient` on `p.destinationChainId`. `msg.value` is the LayerZero
    ///         fee EXCLUSIVELY (quoted precheck; excess refunds to `msg.sender`, never the diamond).
    /// @dev TAXI ONLY (issue #77 Q11): the send is dispatched with EMPTY `oftCmd` (immediate/taxi mode) and
    ///      EMPTY `composeMsg`/`extraOptions` — bus mode (deferred batched sends) and `lzCompose` destination
    ///      hooks are DEFERRED to a future revision. DUST SWEEP: pools truncate `amountLD` to shared decimals,
    ///      so the pool may debit less than was pulled; the exact un-debited remainder is returned to
    ///      `msg.sender` in the same call and the diamond nets zero.
    /// @return guid             The LayerZero message guid.
    /// @return amountSentLD     The amount the pool ACTUALLY debited (post dust truncation).
    /// @return amountReceivedLD The amount credited on the destination (post pool fees).
    function sendToken(SendTokenParams calldata p)
        external
        payable
        returns (bytes32 guid, uint256 amountSentLD, uint256 amountReceivedLD);
}
