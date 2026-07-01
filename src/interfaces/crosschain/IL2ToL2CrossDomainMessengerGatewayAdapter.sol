// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IL2ToL2CrossDomainMessengerGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Admin/read surface of the OP Superchain `L2ToL2CrossDomainMessenger` ERC-7786 gateway adapter. The
///         standard source-gateway ABI (`sendMessage`/`supportsAttribute`) is on `IERC7786GatewaySource`; the
///         inbound delivery callback the messenger invokes on the destination adapter is
///         `receiveCrossChainMessage`. EVM (Superchain) chains only.
/// @dev Unlike the CCIP / LayerZero siblings there is NO native-id translation: the messenger routes by BARE EVM
///      `chainId`, so the trusted-remote registry is a single `mapping(chainId => remoteAdapter)` — the sibling
///      adapter on that chain. Sends target the remote adapter, which relays to the final ERC-7930 recipient
///      encoded in the message envelope. No fee is taken: gas is supplied by the relayer at `relayMessage`, and
///      the messenger itself charges no native value, so `sendMessage` rejects a non-empty `msg.value`.
/// @dev INVERTED INBOUND AUTH (vs. the siblings' "gateway is `msg.sender`" model): the adapter's inbound function
///      is the `_target` the messenger CALLS during `relayMessage`, so `msg.sender` is the messenger predeploy —
///      not the remote gateway. The trusted-remote check is therefore read back out-of-band from the messenger's
///      `crossDomainMessageContext()` (the authenticated `(sender, source)`), NOT from `msg.sender`.
interface IL2ToL2CrossDomainMessengerGatewayAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a trusted remote gateway adapter is registered for a chain.
    event RegisteredRemoteAdapter(uint256 indexed chainId, address remoteAdapter);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice A remote adapter is already registered for this chain (registration is one-shot).
    error RemoteAdapterAlreadyRegistered(uint256 chainId);

    /// @notice A zero address was supplied as a remote adapter.
    error InvalidRemoteAdapter();

    /// @notice The destination chain has no remote adapter registered.
    error UnknownDestinationChain(uint256 chainId);

    /// @notice A non-empty `msg.value` was supplied to `sendMessage`; the messenger takes no native fee.
    error UnexpectedValue(uint256 value);

    /// @notice The inbound callback was not invoked by the `L2ToL2CrossDomainMessenger` predeploy.
    error NotMessenger(address caller);

    /// @notice The authenticated cross-domain `(source, sender)` did not match the registered remote adapter.
    error InvalidOriginGateway(uint256 source, address sender);

    /// @notice The inbound message was already delivered (replay defense-in-depth atop the messenger self-dedup).
    error MessageAlreadyExecuted(uint256 source, bytes32 id);

    /// @notice The recipient's `receiveMessage` did not return the ERC-7786 magic value.
    error RecipientExecutionFailed();

    /// @notice The inbound message's ERC-7930 recipient targets a different chain than this one (defense-in-depth
    ///         against a rogue/misconfigured trusted remote adapter misdirecting delivery).
    error WrongDestinationChain(uint256 chainId);

    // -------------------------------------------------------------------------
    //                                  Reads
    // -------------------------------------------------------------------------

    /// @notice The fixed OP Superchain `L2ToL2CrossDomainMessenger` predeploy this adapter sends to / accepts
    ///         deliveries from (`0x4200000000000000000000000000000000000023`).
    function messenger() external view returns (address);

    /// @notice The trusted remote gateway adapter registered for `chainId` (0 = unset).
    function getRemoteAdapter(uint256 chainId) external view returns (address);

    // -------------------------------------------------------------------------
    //                                  Inbound
    // -------------------------------------------------------------------------

    /// @notice Inbound delivery callback the messenger invokes on THIS adapter during `relayMessage`. Authenticates
    ///         the messenger + the authenticated cross-domain `(source, sender)` against the registered remote
    ///         adapter, de-dups, then hands off to the ERC-7930 `recipient` via the `IERC7786Recipient` handshake.
    /// @param sender    The ERC-7930 sender interoperable address (origin chain + caller).
    /// @param recipient The ERC-7930 recipient interoperable address (must target THIS chain).
    /// @param payload   The opaque message payload delivered to the recipient.
    /// @param nonce     The source-minted monotonic nonce; `(source, nonce)` forms the globally-unique delivery id.
    function receiveCrossChainMessage(
        bytes calldata sender,
        bytes calldata recipient,
        bytes calldata payload,
        uint256 nonce
    ) external;

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Registers a trusted remote gateway adapter (the sibling adapter) for a chain. One-shot. Admin only.
    function registerRemoteAdapter(uint256 chainId, address remoteAdapter) external;
}
