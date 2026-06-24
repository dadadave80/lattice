// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IWormholeGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin community-contracts `WormholeGatewayAdapter` (commit f7e5f08)
///         (https://github.com/OpenZeppelin/openzeppelin-community-contracts/blob/f7e5f08e8fd42023084eb41f4a992d7be897b915/contracts/crosschain/wormhole/WormholeGatewayAdapter.sol)
/// @notice Admin/read/relay surface of the Wormhole ERC-7786 gateway adapter. The standard source-gateway
///         ABI (`sendMessage`/`supportsAttribute`) is on `IERC7786GatewaySource`; the inbound callback is
///         `IWormholeReceiver.receiveWormholeMessages`. EVM chains only; `value` may fund delivery.
/// @dev Two-phase send: `sendMessage` with no attribute stores a pending message and returns a non-zero
///      `sendId`; the sender then calls `requestRelay` (with gas + value) to dispatch it. `sendMessage` with
///      a single `requestRelay` attribute dispatches immediately and returns `bytes32(0)`.
interface IWormholeGatewayAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when an EVM chainId ↔ Wormhole chain-id equivalence is registered.
    event RegisteredChainEquivalence(uint256 indexed chainId, uint16 wormhole);

    /// @notice Emitted when a trusted remote gateway adapter is registered for a chain.
    event RegisteredRemoteGateway(uint256 indexed chainId, address remote);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice More than one attribute was supplied to `sendMessage`.
    error DuplicatedAttribute();

    /// @notice A chain equivalence is already registered for this chainId or Wormhole id.
    error ChainEquivalenceAlreadyRegistered(uint256 chainId);

    /// @notice A remote gateway is already registered for this chain.
    error RemoteGatewayAlreadyRegistered(uint256 chainId);

    /// @notice `requestRelay` referenced a sendId with no pending message.
    error UnknownMessage(bytes32 sendId);

    /// @notice The inbound callback was not invoked by the configured Wormhole relayer.
    error NotWormholeRelayer(address caller);

    /// @notice The inbound source did not match the registered remote gateway for its chain.
    error InvalidOriginGateway(uint16 sourceChain, bytes32 sourceAddress);

    /// @notice The inbound message (chainId, sendId) was already delivered (replay).
    error MessageAlreadyExecuted(uint256 chainId, uint256 sendId);

    /// @notice The recipient's `receiveMessage` did not return the ERC-7786 magic value.
    error RecipientExecutionFailed();

    // -------------------------------------------------------------------------
    //                                  Reads
    // -------------------------------------------------------------------------

    function relayer() external view returns (address);
    function wormholeChainId() external view returns (uint16);
    function getWormholeChain(uint256 chainId) external view returns (uint16);
    function getChainId(uint16 wormhole) external view returns (uint256);
    function getRemoteGateway(uint256 chainId) external view returns (address);

    /// @notice Quote the native cost to relay a message to `recipient` (ERC-7930) with `gasLimit`.
    function quoteRelay(bytes calldata recipient, uint256 gasLimit) external view returns (uint256);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Registers an EVM chainId ↔ Wormhole chain-id equivalence (both directions). Admin only.
    function registerChainEquivalence(uint256 chainId, uint16 wormhole) external;

    /// @notice Registers a trusted remote gateway adapter for a chain. Admin only.
    function registerRemoteGateway(uint256 chainId, address remote) external;

    // -------------------------------------------------------------------------
    //                                   Relay
    // -------------------------------------------------------------------------

    /// @notice Dispatches a previously-stored pending message via the Wormhole relayer.
    /// @param sendId         The non-zero id returned by `sendMessage` (no-attribute path).
    /// @param gasLimit       Destination gas limit for delivery.
    /// @param refundRecipient Address to refund unused relay funds to (on this chain).
    function requestRelay(bytes32 sendId, uint256 gasLimit, address refundRecipient) external payable;
}
