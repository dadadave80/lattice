// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC7786OpenBridge
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin community-contracts `ERC7786OpenBridge` (https://github.com/OpenZeppelin/openzeppelin-community-contracts, commit f7e5f08)
///         (https://github.com/OpenZeppelin/openzeppelin-community-contracts/blob/f7e5f08e8fd42023084eb41f4a992d7be897b915/contracts/crosschain/ERC7786OpenBridge.sol)
/// @notice Admin/read surface of the ERC-7786 OpenBridge: an N-of-M aggregator that fans a message out
///         across M gateways and delivers to the recipient once N independent gateways have attested it.
///         The standard `sendMessage`/`supportsAttribute` are on `IERC7786GatewaySource`; the inbound
///         `receiveMessage` is on `IERC7786Recipient`.
interface IERC7786OpenBridge {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted with the per-gateway send ids when an outbound message is fanned out.
    event OutboxDetails(bytes32 indexed sendId, bytes32[] outbox);

    /// @notice Emitted when a gateway attests an inbound message.
    event Received(bytes32 indexed id, address indexed gateway);

    /// @notice Emitted when an inbound message reaches the threshold and the recipient call succeeds.
    event ExecutionSuccess(bytes32 indexed id);

    /// @notice Emitted when the recipient call fails (the message stays retryable — no revert).
    event ExecutionFailed(bytes32 indexed id);

    /// @notice Emitted when a matching remote bridge is registered for a chain.
    event RegisteredRemoteBridge(bytes bridge);

    /// @notice Emitted when a gateway is added to / removed from the M-set.
    event GatewayAdded(address indexed gateway);
    event GatewayRemoved(address indexed gateway);

    /// @notice Emitted when the N threshold changes.
    event ThresholdUpdated(uint8 threshold);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice `sendMessage` was called with non-zero `msg.value` (native transfer unsupported).
    error UnsupportedNativeTransfer();

    /// @notice A matching remote bridge is already registered for this chain.
    error RemoteBridgeAlreadyRegistered(bytes chain);

    /// @notice The inbound `sender` is not the registered matching bridge for its chain.
    error InvalidCrosschainSender();

    /// @notice The recipient returned a value other than the ERC-7786 magic.
    error InvalidExecutionReturnValue();

    /// @notice The threshold must satisfy `0 < N <= M` (M = number of gateways).
    error ThresholdViolation();

    // -------------------------------------------------------------------------
    //                                  Reads
    // -------------------------------------------------------------------------

    function getGateways() external view returns (address[] memory);
    function getThreshold() external view returns (uint8);
    function getRemoteBridge(bytes calldata chain) external view returns (bytes memory);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    function addGateway(address gateway) external;
    function removeGateway(address gateway) external;
    function setThreshold(uint8 threshold) external;

    /// @notice Registers the matching OpenBridge on a remote chain (full ERC-7930 interoperable address).
    function registerRemoteBridge(bytes calldata bridge) external;
}
