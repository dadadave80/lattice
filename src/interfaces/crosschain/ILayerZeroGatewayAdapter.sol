// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ILayerZeroGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from LayerZero v2 (https://github.com/LayerZero-Labs/LayerZero-v2)
/// @notice Admin/read surface of the LayerZero v2 ERC-7786 gateway adapter. The standard source-gateway ABI
///         (`sendMessage`/`supportsAttribute`) is on `IERC7786GatewaySource`; the inbound callback + path policy
///         are `ILayerZeroReceiver` (`lzReceive`/`allowInitializePath`/`nextNonce`). EVM chains only.
/// @dev LayerZero routes by `uint32` endpoint id (eid), not EVM chainId — the adapter holds a bidirectional
///      chainId ⇄ eid map and a 32-byte trusted `peer` per chain. Sends target the peer, which relays to the
///      final ERC-7930 recipient encoded in the message envelope. The native fee is quoted from the endpoint and
///      paid by `msg.sender` via `msg.value` (excess refunded); the adapter never spends Diamond funds.
interface ILayerZeroGatewayAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when an EVM chainId ↔ LayerZero eid equivalence is registered.
    event RegisteredEid(uint256 indexed chainId, uint32 eid);

    /// @notice Emitted when a trusted 32-byte peer (remote adapter) is registered for a chain.
    event RegisteredPeer(uint256 indexed chainId, bytes32 peer);

    /// @notice Emitted when a destination's executor `lzReceive` gas / native msg.value is configured.
    event ConfiguredDestination(uint256 indexed chainId, uint128 gas, uint128 msgValue);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice An eid equivalence is already registered for this chainId or eid.
    error EidAlreadyRegistered(uint256 chainId);

    /// @notice A peer is already registered for this chain.
    error PeerAlreadyRegistered(uint256 chainId);

    /// @notice The destination chain has no eid and/or no peer registered.
    error UnknownDestinationChain(uint256 chainId);

    /// @notice The destination chain has no executor gas configured (call `configureDestination`).
    error DestinationNotConfigured(uint256 chainId);

    /// @notice The native value supplied was below the quoted LayerZero native fee.
    error InsufficientFee(uint256 provided, uint256 required);

    /// @notice Refunding unspent native value to the sender failed.
    error RefundFailed();

    /// @notice The inbound callback was not invoked by the configured LayerZero endpoint.
    error NotEndpoint(address caller);

    /// @notice The inbound source did not match the registered peer for its chain.
    error InvalidOriginGateway(uint32 srcEid, bytes32 sender);

    /// @notice The inbound message (chainId, LayerZero guid) was already delivered (replay).
    error MessageAlreadyExecuted(uint256 chainId, bytes32 guid);

    /// @notice The recipient's `receiveMessage` did not return the ERC-7786 magic value.
    error RecipientExecutionFailed();

    /// @notice The inbound message's ERC-7930 recipient targets a different chain than this one (defense-in-depth
    ///         against a rogue/misconfigured trusted peer misdirecting delivery).
    error WrongDestinationChain(uint256 chainId);

    // -------------------------------------------------------------------------
    //                                  Reads
    // -------------------------------------------------------------------------

    function endpoint() external view returns (address);
    function getEid(uint256 chainId) external view returns (uint32);
    function getChainId(uint32 eid) external view returns (uint256);
    function getPeer(uint256 chainId) external view returns (bytes32);
    function getDestinationGas(uint256 chainId) external view returns (uint128);
    function getDestinationMsgValue(uint256 chainId) external view returns (uint128);

    /// @notice Quotes the LayerZero native fee to send `payload` to `recipient` (ERC-7930).
    function quoteFee(bytes calldata recipient, bytes calldata payload) external view returns (uint256);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Registers an EVM chainId ↔ LayerZero eid equivalence (both directions). Admin only.
    function registerEid(uint256 chainId, uint32 eid) external;

    /// @notice Registers a trusted 32-byte peer (remote adapter) for a chain. Admin only.
    function registerPeer(uint256 chainId, bytes32 peer) external;

    /// @notice Configures a destination's executor `lzReceive` gas and native msg.value. Admin only.
    function configureDestination(uint256 chainId, uint128 gas, uint128 msgValue) external;
}
