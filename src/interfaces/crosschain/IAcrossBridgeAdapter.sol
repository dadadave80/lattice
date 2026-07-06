// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAcrossBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Across (https://github.com/across-protocol/contracts)
/// @notice Read / action surface of the Across v3 intent/optimistic token-bridge adapter. Across is an
///         INTENT bridge: `deposit` escrows the input token on this chain and a relayer FRONTS the output token
///         on the destination (later reimbursed via UMA optimistic settlement) — there is NO guaranteed fill: if
///         no relayer fills before `fillDeadline`, Across refunds the input token ON THIS CHAIN to the deposit's
///         `depositor` (always the calling user, never the diamond). This is NOT an ERC-7786 message gateway
///         (no `receiveId`, no source attribution) and NOT burn/mint — it is never routed through OpenBridge.
/// @dev Across chain ids are passed RAW by callers (there is no admin-managed domain table and no admin surface
///      at all); quote-derived fields (`quoteTimestamp`, `fillDeadline`, `outputAmount`, `exclusiveRelayer`,
///      `exclusivityParameter`) come from the off-chain Across quote API and are validated by the SpokePool.
///      The inbound `handleV3AcrossMessage` surface is authenticated to the SpokePool only and merely emits —
///      fills are relayer-pushed and optimistic (NOT yet UMA-finalized when the hook runs), so received funds /
///      message content must be treated as reversible-until-finalized by any consumer.
interface IAcrossBridgeAdapter {
    // -------------------------------------------------------------------------
    //                                  Structs
    // -------------------------------------------------------------------------

    /// @notice Caller-supplied parameters of an Across v3 `deposit` (struct avoids stack-too-deep).
    struct DepositParams {
        /// @notice ERC-7930 interoperable address of the destination recipient (20-byte EVM or up-to-32-byte
        ///         non-EVM address field; down-converted to a right-aligned `bytes32`).
        bytes recipient;
        /// @notice Destination-chain token the relayer fronts, raw right-aligned `bytes32`. Must be non-zero.
        bytes32 outputToken;
        /// @notice Token escrowed on THIS chain (ERC-20 only in v1; wrap native first).
        address inputToken;
        /// @notice Amount of `inputToken` pulled from the caller and escrowed in the SpokePool.
        uint256 inputAmount;
        /// @notice Amount of `outputToken` the recipient receives at fill time (quote-derived; inputAmount
        ///         minus relayer/LP fees).
        uint256 outputAmount;
        /// @notice Across chain id of the destination chain (raw; for EVM destinations this is the EVM chainId
        ///         and is cross-checked against the ERC-7930 recipient's chain reference).
        uint256 destinationChainId;
        /// @notice Only relayer allowed to fill before the exclusivity deadline (`bytes32(0)` = none).
        bytes32 exclusiveRelayer;
        /// @notice Quote-API timestamp the LP fee is priced at (SpokePool bounds its age).
        uint32 quoteTimestamp;
        /// @notice Destination-chain timestamp after which the deposit is refundable to the depositor.
        uint32 fillDeadline;
        /// @notice 0 = no exclusivity; small values = offset from now; large values = absolute timestamp.
        uint32 exclusivityParameter;
        /// @notice Arbitrary bytes delivered to the recipient via `handleV3AcrossMessage` at fill time.
        bytes message;
    }

    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when an Across v3 deposit intent is escrowed on this chain toward `destinationChainId`.
    event AcrossDepositSent(
        address indexed sender,
        uint256 indexed destinationChainId,
        address inputToken,
        uint256 inputAmount,
        bytes32 outputToken,
        uint256 outputAmount,
        bytes32 recipient
    );

    /// @notice Emitted when the SpokePool delivers a fill-time message to this diamond. OPTIMISTIC: the fill is
    ///         relayer-pushed and not yet UMA-finalized when this fires.
    /// @dev NOT AN AUTHENTICATED MESSAGE. SpokePool authentication is not deposit authenticity: ANY party on
    ///      any Across origin chain can create a deposit whose recipient is this diamond, so `tokenSent`,
    ///      `amount`, `relayer` and `message` are all attacker-influenceable, and Across provides no on-chain
    ///      source attribution or `receiveId`. Consumers (off-chain or future facets) MUST validate deposit
    ///      provenance independently before acting on this event or on the received funds.
    event AcrossMessageReceived(address indexed tokenSent, uint256 amount, address indexed relayer, bytes message);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice A required address (the SpokePool at init, or `inputToken`) was the zero address.
    error AcrossZeroAddress();

    /// @notice The deposit `inputAmount` was zero.
    error AcrossZeroAmount();

    /// @notice The deposit `outputToken` was `bytes32(0)` (the SpokePool rejects it; fail fast here).
    error AcrossZeroOutputToken();

    /// @notice The deposit targeted this chain (`destinationChainId == block.chainid`).
    error AcrossSameChainDeposit(uint256 chainId);

    /// @notice The ERC-7930 recipient declares an eip-155 chain that differs from `destinationChainId`.
    error AcrossDestinationMismatch(uint256 declaredChainId, uint256 givenChainId);

    /// @notice The chain reference decoded from the ERC-7930 recipient does not fit in a uint256.
    error AcrossChainReferenceTooLong(uint256 length);

    /// @notice `handleV3AcrossMessage` was called by anyone other than the configured SpokePool.
    error AcrossNotSpokePool(address caller);

    // -------------------------------------------------------------------------
    //                                  Reads
    // -------------------------------------------------------------------------

    /// @notice The LOCAL chain's canonical Across v3 SpokePool (set once at init, no admin surface).
    function spokePool() external view returns (address);

    // -------------------------------------------------------------------------
    //                                  Actions
    // -------------------------------------------------------------------------

    /// @notice Escrows `params.inputAmount` of `params.inputToken` (pulled from `msg.sender`) as an Across v3
    ///         deposit intent toward the ERC-7930 `params.recipient` on `params.destinationChainId`.
    /// @dev REFUND SAFETY: the deposit's `depositor` is always `msg.sender` (the calling user) — NEVER the
    ///      diamond — because Across refunds an expired unfilled deposit ON THIS CHAIN to `depositor`, and
    ///      `depositor` alone may speed up the deposit. NOT payable: ERC-20 inputs only in v1 (the SpokePool
    ///      requires `msg.value == 0` for non-wrapped-native inputs; native ETH users wrap first). Approves the
    ///      SpokePool for EXACTLY `inputAmount`, then resets the allowance to 0.
    function deposit(DepositParams calldata params) external;

    /// @notice SpokePool-invoked fill-time delivery hook (see the vendored {AcrossMessageHandler}): reverts
    ///         {AcrossNotSpokePool} unless called by the configured SpokePool, then emits
    ///         {AcrossMessageReceived}. NOTHING else in v1 — no handler registry; the diamond itself is the
    ///         recipient and other facets manage the received funds.
    /// @dev OPTIMISTIC: fills are relayer-pushed and NOT yet UMA-finalized when this runs — treat received
    ///      funds / message content as reversible-until-finalized. Never routed into OpenBridge (no M-of-N
    ///      confirmation, no `receiveId`).
    function handleV3AcrossMessage(address tokenSent, uint256 amount, address relayer, bytes calldata message) external;
}
