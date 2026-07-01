// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IL1ToL2CrossDomainMessengerGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Admin/read surface of the canonical OP Stack L1<->L2 `CrossDomainMessenger` ERC-7786 gateway adapter.
///         The standard source-gateway ABI (`sendMessage`/`supportsAttribute`) is on `IERC7786GatewaySource`; the
///         inbound delivery callback the messenger invokes on the destination adapter is `receiveCrossChainMessage`.
/// @dev Unlike the L2<->L2 interop sibling there is NO `chainId => remote` map: a canonical L1<->L2 pair has
///      exactly ONE other domain, so the trusted remote is a SINGLE fixed counterpart — `(_counterpartChainId,
///      _counterpartAdapter)` (the sibling adapter on the paired domain) plus a fixed `_minGasLimit` the messenger
///      relays with. Sends target the counterpart adapter, which relays to the final ERC-7930 recipient encoded in
///      the message envelope. No fee is taken: `sendMessage` rejects a non-empty `msg.value`.
/// @dev INVERTED INBOUND AUTH (vs. the siblings' "gateway is `msg.sender`" model): the adapter's inbound function
///      is the `_target` the messenger CALLS during relay, so `msg.sender` is the L2 messenger predeploy — not the
///      counterpart gateway. The trusted-remote check is therefore read back out-of-band from the messenger's
///      `xDomainMessageSender()` (the authenticated counterpart sender), NOT from `msg.sender`.
/// @dev L2->L1 (withdrawal) messages finalize only after the withdrawal challenge window (handled off-chain by the
///      messenger/portal); the adapter is direction-agnostic and identical on both domains.
interface IL1ToL2CrossDomainMessengerGatewayAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when the fixed counterpart (paired-domain chainId + sibling adapter) is configured.
    event CounterpartConfigured(uint256 indexed chainId, address adapter);

    /// @notice Emitted when the relay `minGasLimit` is configured.
    event MinGasLimitConfigured(uint32 minGasLimit);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice A zero address was supplied as the counterpart adapter.
    error InvalidCounterpartAdapter();

    /// @notice A zero relay `minGasLimit` was supplied (delivery would out-of-gas).
    error InvalidMinGasLimit();

    /// @notice The destination chain is not the configured counterpart chain.
    error UnknownDestinationChain(uint256 chainId);

    /// @notice A non-empty `msg.value` was supplied to `sendMessage`; the adapter takes no native fee.
    error UnexpectedValue(uint256 value);

    /// @notice The inbound callback was not invoked by the `L2CrossDomainMessenger` predeploy.
    error NotMessenger(address caller);

    /// @notice The authenticated counterpart sender (`xDomainMessageSender`) did not match the configured
    ///         counterpart adapter.
    error InvalidOriginGateway(address sender);

    /// @notice The inbound message was already delivered (replay defense-in-depth atop the messenger self-dedup).
    error MessageAlreadyExecuted(bytes32 id);

    /// @notice The recipient's `receiveMessage` did not return the ERC-7786 magic value.
    error RecipientExecutionFailed();

    /// @notice The inbound message's ERC-7930 recipient targets a different chain than this one (defense-in-depth
    ///         against a rogue/misconfigured counterpart adapter misdirecting delivery).
    error WrongDestinationChain(uint256 chainId);

    // -------------------------------------------------------------------------
    //                                  Reads
    // -------------------------------------------------------------------------

    /// @notice The fixed OP Stack L2 `CrossDomainMessenger` predeploy this adapter sends to / accepts deliveries
    ///         from (`0x4200000000000000000000000000000000000007`).
    function messenger() external view returns (address);

    /// @notice The configured counterpart (paired-domain) chain id (0 = unset).
    function counterpartChainId() external view returns (uint256);

    /// @notice The configured counterpart gateway adapter on the paired domain (0 = unset).
    function counterpartAdapter() external view returns (address);

    /// @notice The `minGasLimit` the messenger relays outbound messages with.
    function minGasLimit() external view returns (uint32);

    // -------------------------------------------------------------------------
    //                                  Inbound
    // -------------------------------------------------------------------------

    /// @notice Inbound delivery callback the messenger invokes on THIS adapter during relay. Authenticates the
    ///         messenger + the authenticated counterpart sender against the configured counterpart adapter,
    ///         de-dups, then hands off to the ERC-7930 `recipient` via the `IERC7786Recipient` handshake.
    /// @param sender    The ERC-7930 sender interoperable address (origin chain + caller).
    /// @param recipient The ERC-7930 recipient interoperable address (must target THIS chain).
    /// @param payload   The opaque message payload delivered to the recipient.
    /// @param nonce     The source-minted monotonic nonce; `(counterpartChainId, nonce)` forms the globally-unique
    ///                  delivery id.
    function receiveCrossChainMessage(
        bytes calldata sender,
        bytes calldata recipient,
        bytes calldata payload,
        uint256 nonce
    ) external;

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Configures the fixed counterpart (paired-domain chainId + sibling adapter). Rejects a zero adapter.
    ///         Admin only.
    function setCounterpart(uint256 chainId, address adapter) external;

    /// @notice Configures the relay `minGasLimit`. Admin only.
    function setMinGasLimit(uint32 newMinGasLimit) external;
}
