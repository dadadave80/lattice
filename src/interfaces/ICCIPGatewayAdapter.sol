// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ICCIPGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Admin/read surface of the Chainlink CCIP ERC-7786 gateway adapter. The standard source-gateway ABI
///         (`sendMessage`/`supportsAttribute`) is on `IERC7786GatewaySource`; the inbound callback is
///         `IAny2EVMMessageReceiver.ccipReceive`. EVM chains only.
/// @dev CCIP routes by `uint64` chain selector, not EVM chainId — the adapter holds a bidirectional
///      chainId ⇄ selector map. Sends go to the registered remote adapter on the destination chain, which
///      relays to the final ERC-7930 recipient encoded in the payload. Fees are paid in the configured fee
///      token (`address(0)` ⇒ native via `msg.value`, else an ERC-20 such as LINK pulled from the sender).
interface ICCIPGatewayAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when an EVM chainId ↔ CCIP chain-selector equivalence is registered.
    event RegisteredChainSelector(uint256 indexed chainId, uint64 selector);

    /// @notice Emitted when a trusted remote gateway adapter is registered for a chain.
    event RegisteredRemoteGateway(uint256 indexed chainId, address remote);

    /// @notice Emitted when a destination's delivery gas limit / ordering flag is configured.
    event ConfiguredDestination(uint256 indexed chainId, uint256 gasLimit, bool allowOutOfOrderExecution);

    /// @notice Emitted when the fee token is set (`address(0)` ⇒ native).
    event SetFeeToken(address indexed feeToken);

    /// @notice Emitted when a source chain's CCV (Cross-Chain Verifier) requirements / finality are configured.
    event ConfiguredCCV(
        uint256 indexed chainId,
        address[] requiredCCVs,
        address[] optionalCCVs,
        uint8 optionalThreshold,
        bytes4 allowedFinalityConfig
    );

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice A chain selector equivalence is already registered for this chainId or selector.
    error ChainSelectorAlreadyRegistered(uint256 chainId);

    /// @notice A remote gateway is already registered for this chain.
    error RemoteGatewayAlreadyRegistered(uint256 chainId);

    /// @notice The destination chain has no selector and/or no remote gateway registered.
    error UnknownDestinationChain(uint256 chainId);

    /// @notice The destination chain has no delivery gas limit configured (call `configureDestination`).
    error DestinationNotConfigured(uint256 chainId);

    /// @notice The native value supplied was below the quoted CCIP fee.
    error InsufficientFee(uint256 provided, uint256 required);

    /// @notice Refunding unspent native value to the sender failed.
    error RefundFailed();

    /// @notice The optional-CCV threshold exceeds the number of optional CCVs supplied.
    error InvalidCCVThreshold(uint8 threshold, uint256 optionalCount);

    /// @notice The inbound callback was not invoked by the configured CCIP router.
    error NotRouter(address caller);

    /// @notice The inbound source did not match the registered remote gateway for its chain.
    error InvalidOriginGateway(uint64 sourceChainSelector, bytes sender);

    /// @notice The inbound message (chainId, CCIP messageId) was already delivered (replay).
    error MessageAlreadyExecuted(uint256 chainId, bytes32 messageId);

    /// @notice The recipient's `receiveMessage` did not return the ERC-7786 magic value.
    error RecipientExecutionFailed();

    // -------------------------------------------------------------------------
    //                                  Reads
    // -------------------------------------------------------------------------

    function router() external view returns (address);
    function feeToken() external view returns (address);
    function getChainSelector(uint256 chainId) external view returns (uint64);
    function getChainId(uint64 selector) external view returns (uint256);
    function getRemoteGateway(uint256 chainId) external view returns (address);
    function getDestinationGasLimit(uint256 chainId) external view returns (uint256);
    function getAllowOutOfOrderExecution(uint256 chainId) external view returns (bool);

    /// @notice Quotes the CCIP fee (in the configured fee token) to send `payload` to `recipient` (ERC-7930).
    function quoteFee(bytes calldata recipient, bytes calldata payload) external view returns (uint256);

    /// @notice Returns the configured CCV requirements / finality for inbound messages from `chainId`
    ///         (all-empty / `bytes4(0)` ⇒ unconfigured: CCIP defaults, require full finality).
    function getCCVConfig(uint256 chainId)
        external
        view
        returns (
            address[] memory requiredCCVs,
            address[] memory optionalCCVs,
            uint8 optionalThreshold,
            bytes4 allowedFinalityConfig
        );

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Registers an EVM chainId ↔ CCIP chain-selector equivalence (both directions). Admin only.
    function registerChainSelector(uint256 chainId, uint64 selector) external;

    /// @notice Registers a trusted remote gateway adapter for a chain. Admin only.
    function registerRemoteGateway(uint256 chainId, address remote) external;

    /// @notice Configures a destination's delivery gas limit and out-of-order execution flag. Admin only.
    function configureDestination(uint256 chainId, uint256 gasLimit, bool allowOutOfOrderExecution) external;

    /// @notice Sets the fee token (`address(0)` ⇒ native). Admin only.
    function setFeeToken(address feeToken) external;

    /// @notice Configures the CCV requirements + allowed finality returned to the CCIP router for inbound
    ///         messages from `chainId`. `optionalThreshold` must be ≤ `optionalCCVs.length`. Admin only.
    /// @param allowedFinalityConfig CCIP finality flag; `bytes4(0)` requires full finality (the safe default).
    function configureCCV(
        uint256 chainId,
        address[] calldata requiredCCVs,
        address[] calldata optionalCCVs,
        uint8 optionalThreshold,
        bytes4 allowedFinalityConfig
    ) external;
}
