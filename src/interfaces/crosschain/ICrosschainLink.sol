// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ICrosschainLink
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin `CrosschainLinked` v5.6.1 (https://github.com/OpenZeppelin/openzeppelin-contracts)
///         (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/crosschain/CrosschainLinked.sol)
/// @notice Admin/read surface for the {CrosschainLink} facet: an ERC-7786 send + receive endpoint that
///         registers per-chain `(gateway, counterpart)` links and routes inbound messages to handlers by
///         a leading 4-byte payload tag.
/// @dev The receive entrypoint `receiveMessage` is declared by `IERC7786Recipient`; the facet implements
///      both. Chains and counterparts are ERC-7930 binary interoperable addresses: a `chain` is a
///      "chain-only" interoperable address (empty address), a `counterpart` is a full one (chain + address).
interface ICrosschainLink {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a link is registered or overridden. `counterpart` is a full interoperable address.
    event LinkRegistered(address gateway, bytes counterpart);

    /// @notice Emitted when a message handler is registered (or cleared, when `handler` is zero) for a tag.
    event HandlerRegistered(bytes4 indexed tag, address handler);

    /// @notice Emitted when an inbound message is authenticated, de-duplicated, and dispatched to a handler.
    event MessageProcessed(bytes32 indexed receiveId, bytes4 indexed tag, address handler);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice A link already exists for `chain` and `allowOverride` was false. `chain` is chain-only.
    error CrosschainLinkAlreadyRegistered(bytes chain);

    /// @notice The caller (`gateway`) is not the registered gateway for the source chain of `sender`.
    error CrosschainUnauthorizedGateway(address gateway, bytes sender);

    /// @notice `receiveId` has already been processed (replay protection).
    error CrosschainMessageAlreadyProcessed(bytes32 receiveId);

    /// @notice No handler is registered for the payload's leading 4-byte `tag`.
    error CrosschainHandlerNotRegistered(bytes4 tag);

    /// @notice The payload is shorter than the 4-byte handler tag.
    error CrosschainInvalidPayload();

    /// @notice A zero gateway address was supplied to `setLink`.
    error CrosschainZeroGateway();

    // -------------------------------------------------------------------------
    //                                  Reads
    // -------------------------------------------------------------------------

    /// @notice Returns the gateway and counterpart registered for a source chain.
    /// @param chain A "chain-only" ERC-7930 interoperable address (empty address).
    /// @return gateway     The ERC-7786 gateway trusted for `chain`.
    /// @return counterpart The full interoperable address authorized to send from `chain`.
    function getLink(bytes calldata chain) external view returns (address gateway, bytes memory counterpart);

    /// @notice Returns the handler registered for a message tag (zero if none).
    function getHandler(bytes4 tag) external view returns (address handler);

    /// @notice Returns whether a `receiveId` from `gateway` has already been processed (keyed per-gateway,
    ///         as ERC-7786 only guarantees receiveId uniqueness for the calling gateway).
    function isProcessed(address gateway, bytes32 receiveId) external view returns (bool);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Registers (or overrides) the gateway + counterpart for the counterpart's source chain.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`. Reverts `CrosschainLinkAlreadyRegistered` if a link
    ///      exists and `allowOverride` is false.
    /// @param gateway       The ERC-7786 gateway for this chain (must implement `supportsAttribute`).
    /// @param counterpart   The full interoperable address of the remote counterpart.
    /// @param allowOverride Whether to overwrite an existing link for the chain.
    function setLink(address gateway, bytes calldata counterpart, bool allowOverride) external;

    /// @notice Registers a handler for inbound messages whose payload starts with `tag` (zero to clear).
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`.
    function setHandler(bytes4 tag, address handler) external;

    /// @notice Sends a message to the counterpart registered for `chain` via its ERC-7786 gateway.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param chain      A "chain-only" interoperable address selecting the destination link.
    /// @param payload    The message payload (handlers expect a leading 4-byte tag on the receiving side).
    /// @param attributes ERC-7786 gateway attributes (may be empty).
    /// @return sendId    The gateway-assigned send id (zero if no further processing is needed).
    function sendMessage(bytes calldata chain, bytes calldata payload, bytes[] calldata attributes)
        external
        returns (bytes32 sendId);
}
