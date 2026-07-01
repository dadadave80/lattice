// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IZetaChainGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Admin/read surface of the ZetaChain `GatewayEVM` ERC-7786 gateway adapter. The standard source-gateway
///         ABI (`sendMessage`/`supportsAttribute`) is on `IERC7786GatewaySource`; the inbound delivery hook the
///         `GatewayEVM` invokes on this adapter is `Callable.onCall`. EVM chains only.
/// @dev HUB-ROUTED (vs. the direct-peer CCIP/LayerZero/OP siblings): a ZetaChain route terminates at a ZEVM
///      UNIVERSAL APP (the hub), not a direct remote adapter. The trusted-remote registry therefore maps a hub
///      `chainId` to its ZEVM universal app, and MUST keep BOTH a forward map (`chainId => app`) and a reverse map
///      (`app => chainId`): inbound `onCall` only gives `context.sender = the app` (NOT a chainId), so the reverse
///      map is how the source chainId is recovered for auth + the delivery-id namespace.
/// @dev INVERTED INBOUND AUTH: `onCall` is invoked by the `GatewayEVM` (driven by the ZetaChain TSS/observer set),
///      so `msg.sender` is the gateway — not the ZEVM app. Trust is established by matching `context.sender`
///      against the reverse registry (a registered ZEVM app), then recovering its source chainId.
/// @dev The `GatewayEVM` is a DEPLOYED contract whose address varies per connected chain (NOT a fixed predeploy),
///      so it is stored at init and mutable via an admin setter. `sendMessage` forwards `msg.value` as the native
///      messaging fee (no on-chain quote or refund from the gateway). Per-message ERC-7786 `RevertOptions`
///      attributes are DEFERRED (#77 open question #8): an admin-configured default `onRevertGasLimit` is used.
interface IZetaChainGatewayAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when the ZetaChain `GatewayEVM` address is set (init or admin update).
    event GatewaySet(address indexed gateway);

    /// @notice Emitted when a trusted remote ZEVM universal app (hub) is registered for a chain (both maps).
    event RegisteredRemote(uint256 indexed chainId, address remoteApp);

    /// @notice Emitted when the default `onRevertGasLimit` used to build per-message `RevertOptions` is set.
    event DefaultOnRevertGasLimitSet(uint256 onRevertGasLimit);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice A zero address was supplied as the `GatewayEVM`.
    error InvalidGateway();

    /// @notice A zero address was supplied as a remote ZEVM universal app.
    error InvalidRemote();

    /// @notice A remote app is already registered for this chain, or this app is already mapped (one-shot).
    error RemoteAlreadyRegistered(uint256 chainId);

    /// @notice The destination chain has no remote ZEVM universal app (hub route) registered.
    error UnknownDestinationChain(uint256 chainId);

    /// @notice The inbound `onCall` was not invoked by the configured ZetaChain `GatewayEVM`.
    error NotGateway(address caller);

    /// @notice The inbound `context.sender` is not a registered trusted ZEVM universal app.
    error InvalidOriginApp(address app);

    /// @notice The envelope's self-declared source chain does not match the source chain registered for the ZEVM
    ///         app that delivered it (a shared/misconfigured app fronting the wrong corridor).
    error SourceChainMismatch(uint256 declaredChainId, uint256 registeredChainId);

    /// @notice The inbound message (source chainId, delivery id) was already delivered (replay).
    error MessageAlreadyExecuted(uint256 chainId, bytes32 id);

    /// @notice The inbound message's ERC-7930 recipient targets a different chain than this one (defense-in-depth
    ///         against a rogue/misconfigured trusted remote misdirecting delivery).
    error WrongDestinationChain(uint256 chainId);

    /// @notice The recipient's `receiveMessage` did not return the ERC-7786 magic value.
    error RecipientExecutionFailed();

    // -------------------------------------------------------------------------
    //                                  Reads
    // -------------------------------------------------------------------------

    /// @notice The ZetaChain `GatewayEVM` this adapter dispatches to / accepts `onCall` deliveries from.
    function gateway() external view returns (address);

    /// @notice The trusted remote ZEVM universal app (hub) registered for `chainId` (0 = unset).
    function getRemoteApp(uint256 chainId) external view returns (address);

    /// @notice The source `chainId` a trusted remote ZEVM universal app resolves to (0 = unset).
    function getChainIdForApp(address remoteApp) external view returns (uint256);

    /// @notice The default `onRevertGasLimit` used to build per-message `RevertOptions`.
    function defaultOnRevertGasLimit() external view returns (uint256);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Sets the ZetaChain `GatewayEVM` address. Rejects zero. Admin only.
    function setGateway(address gateway) external;

    /// @notice Registers a trusted remote ZEVM universal app (hub) for a chain in BOTH maps. One-shot. Admin only.
    function registerRemote(uint256 chainId, address remoteApp) external;

    /// @notice Sets the default `onRevertGasLimit` used to build per-message `RevertOptions`. Admin only.
    function setDefaultOnRevertGasLimit(uint256 onRevertGasLimit) external;
}
