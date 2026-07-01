// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ISuperchainETHBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Surface of the OP Stack `SuperchainETHBridge` interop adapter facet: a thin, OUTBOUND-ONLY payable
///         passthrough that forwards `msg.value` to the canonical `SuperchainETHBridge` predeploy
///         (`0x4200000000000000000000000000000000000024`) to bridge native ETH to another Superchain chain.
/// @dev Native-ETH interop ONLY (Superchain EVM chains, bare `chainId`) — this is NOT the removed
///      `SuperchainTokenBridge`/`SuperchainERC20` model (which OP dropped from contracts after v5.0.0), and NOT
///      an `IERC7786GatewaySource`. The adapter holds no ETH and has no inbound surface: the destination
///      `relayETH` is executed by the messenger on the predeploy itself, which force-sends ETH straight to the
///      recipient. Stateless — the predeploy address is a compile-time constant, so there is no config, no
///      trusted-remote registry, and no admin surface.
interface ISuperchainETHBridgeAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when native ETH is sent toward a destination Superchain chain.
    /// @param from      The caller that funded the bridge (`msg.sender`).
    /// @param to        The recipient on the destination chain.
    /// @param amount    The ETH amount bridged (`msg.value`).
    /// @param chainId   The destination chain id.
    /// @param msgHash   The `L2ToL2CrossDomainMessenger` message hash returned by the predeploy.
    event ETHSent(address indexed from, address indexed to, uint256 amount, uint256 indexed chainId, bytes32 msgHash);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice A zero recipient address was supplied.
    error InvalidRecipient();

    /// @notice A zero `msg.value` was supplied (nothing to bridge).
    error ZeroValue();

    /// @notice The destination chain is this chain — bridging to the local chain would burn ETH with an
    ///         unrelayable message (the messenger rejects same-chain sends); reject it early with a clear error.
    error SameChain();

    // -------------------------------------------------------------------------
    //                                  Reads
    // -------------------------------------------------------------------------

    /// @notice The fixed `SuperchainETHBridge` predeploy this adapter forwards to
    ///         (`0x4200000000000000000000000000000000000024`).
    function bridge() external pure returns (address);

    // -------------------------------------------------------------------------
    //                                  Outbound
    // -------------------------------------------------------------------------

    /// @notice Bridges `msg.value` native ETH to `to` on Superchain chain `chainId` via the predeploy.
    /// @param to      The recipient on the destination chain (must be non-zero).
    /// @param chainId The destination chain id.
    /// @return msgHash The `L2ToL2CrossDomainMessenger` message hash of the relay message.
    function sendETH(address to, uint256 chainId) external payable returns (bytes32 msgHash);
}
