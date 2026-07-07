// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IHyperlaneGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Hyperlane (https://github.com/hyperlane-xyz/hyperlane-monorepo)
/// @notice Admin/read surface of the Hyperlane ERC-7786 gateway adapter. The standard source-gateway ABI
///         (`sendMessage`/`supportsAttribute`) is on `IERC7786GatewaySource`; the inbound callback is the
///         Mailbox-invoked `IMessageRecipient.handle`. EVM chains only.
/// @dev Hyperlane routes by `uint32` domain — usually equal to the EVM chainId but NOT guaranteed — so the
///      adapter holds an admin-registered bidirectional chainId ⇄ domain map (never inferred) and a 32-byte
///      trusted remote (the counterpart adapter) per chain. Sends target the trusted remote, which relays to
///      the final ERC-7930 recipient encoded in the wire envelope; the interchain gas fee is quoted from the
///      Mailbox (`quoteDispatch`) and paid by `msg.sender` via `msg.value` (the default hook refunds surplus
///      to the sending user — the refundAddress in the synthesized StandardHookMetadata). v1 uses the Mailbox
///      DEFAULT ISM; pinning a Lattice-custom ISM (implementing `interchainSecurityModule()` on the facet) is
///      a compatible additive follow-up.
interface IHyperlaneGatewayAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when an EVM chainId ↔ Hyperlane domain equivalence is registered.
    event RegisteredDomain(uint256 indexed chainId, uint32 domain);

    /// @notice Emitted when the trusted 32-byte remote (counterpart adapter) for a chain is set (tunable).
    event RegisteredRemote(uint256 indexed chainId, bytes32 remote);

    /// @notice Emitted when a destination's `handle` gas limit is configured (tunable; 0 = adapter default).
    event ConfiguredDestination(uint256 indexed chainId, uint256 gasLimit);

    /// @notice Emitted on every outbound dispatch, binding the suite-level ERC-7786 `sendId` to the Hyperlane
    ///         `messageId` minted by the Mailbox (the id `Mailbox.delivered` is keyed by).
    event HyperlaneMessageDispatched(bytes32 indexed sendId, bytes32 indexed messageId, uint32 destinationDomain);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice The Mailbox wired at init was the zero address.
    error HyperlaneZeroMailbox();

    /// @notice A domain equivalence is already registered for this chainId or domain (fail-loud, both maps).
    error HyperlaneDomainAlreadyRegistered(uint256 chainId, uint32 domain);

    /// @notice The domain being registered was 0 (0 is the unset sentinel of the chainId ⇒ domain map).
    error HyperlaneZeroDomain();

    /// @notice The trusted remote being registered was bytes32(0) (0 is the unset sentinel).
    error HyperlaneZeroRemote();

    /// @notice The destination chain has no domain and/or no trusted remote registered.
    error HyperlaneUnknownDestinationChain(uint256 chainId);

    /// @notice The native value supplied was below the Mailbox `quoteDispatch` fee.
    error HyperlaneInsufficientFee(uint256 provided, uint256 required);

    /// @notice The inbound callback was not invoked by the configured Hyperlane Mailbox.
    error HyperlaneNotMailbox(address caller);

    /// @notice The inbound origin domain is unknown or the 32-byte sender is not the trusted remote.
    error HyperlaneInvalidOriginGateway(uint32 origin, bytes32 sender);

    /// @notice The inbound message (chainId, sendId) was already delivered (replay).
    error HyperlaneMessageAlreadyExecuted(uint256 chainId, bytes32 sendId);

    /// @notice The recipient's `receiveMessage` did not return the ERC-7786 magic value.
    error HyperlaneRecipientExecutionFailed();

    /// @notice The inbound message's ERC-7930 recipient targets a different chain than this one
    ///         (defense-in-depth against a rogue/misconfigured trusted remote misdirecting delivery).
    error HyperlaneWrongDestinationChain(uint256 chainId);

    /// @notice The Mailbox forwarded native value with `handle` — the adapter never expects value-bearing
    ///         messages in v1 (the interface forces `payable`, so stray value is rejected explicitly).
    error HyperlaneUnexpectedValue(uint256 value);

    // -------------------------------------------------------------------------
    //                                  Reads
    // -------------------------------------------------------------------------

    /// @notice The Hyperlane Mailbox the adapter dispatches to and accepts `handle` deliveries from.
    function mailbox() external view returns (address);

    /// @notice The Hyperlane domain registered for `chainId` (0 = unset).
    function domainOf(uint256 chainId) external view returns (uint32);

    /// @notice The EVM chainId registered for `domain` (0 = unset).
    function chainIdOf(uint32 domain) external view returns (uint256);

    /// @notice The trusted 32-byte remote (counterpart adapter) registered for `chainId` (0 = unset).
    function trustedRemoteOf(uint256 chainId) external view returns (bytes32);

    /// @notice The configured `handle` gas limit for `chainId` (0 = unset; sends fall back to the adapter
    ///         default).
    function destGasLimitOf(uint256 chainId) external view returns (uint256);

    /// @notice Quotes the Mailbox fee to send `payload` to `recipient` (ERC-7930), synthesizing the same
    ///         wire envelope + StandardHookMetadata a real send would dispatch.
    function quoteFee(bytes calldata recipient, bytes calldata payload) external view returns (uint256);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Registers an EVM chainId ↔ Hyperlane domain equivalence (both directions, fail-loud — chain
    ///         identities are never remapped). Admin only.
    function registerDomain(uint256 chainId, uint32 domain) external;

    /// @notice Sets the trusted 32-byte remote (counterpart adapter) for a chain. Tunable. Admin only.
    function registerRemote(uint256 chainId, bytes32 remote) external;

    /// @notice Configures a destination's `handle` gas limit (0 = use the adapter default). Tunable.
    ///         Admin only.
    function configureDestination(uint256 chainId, uint256 gasLimit) external;
}
