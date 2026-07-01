// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ISuperchainETHBridge
/// @notice Minimal vendored subset of the OP Stack `SuperchainETHBridge` predeploy
///         (`0x4200000000000000000000000000000000000024`) — the canonical native-ETH interop bridge across the
///         Superchain interop set. Only the outbound `sendETH` entrypoint is vendored; inbound `relayETH` is
///         invoked by the `L2ToL2CrossDomainMessenger` on the predeploy ITSELF (never on an integrator), so an
///         integrating diamond has no inbound surface to implement.
/// @dev Verified against ethereum-optimism/optimism `develop` @ b3e0997
///      (packages/contracts-bedrock/interfaces/L2/ISuperchainETHBridge.sol), redeclared at pragma ^0.8.30.
///      `sendETH` burns `msg.value` via the `ETHLiquidity` predeploy, messages the destination chain through the
///      `L2ToL2CrossDomainMessenger`, and the destination force-sends the ETH to `_to` — so the recipient must
///      NOT expect a call. Superchain (EVM) chains only; routed by bare `chainId`.
interface ISuperchainETHBridge {
    /// @notice Sends `msg.value` ETH to `_to` on chain `_chainId` over the Superchain interop messenger.
    /// @param _to      The recipient address on the destination chain.
    /// @param _chainId The destination chain id (bare EVM chain id).
    /// @return msgHash_ The `L2ToL2CrossDomainMessenger` message hash of the relay message.
    function sendETH(address _to, uint256 _chainId) external payable returns (bytes32 msgHash_);
}
