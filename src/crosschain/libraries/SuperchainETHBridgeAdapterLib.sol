// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {ISuperchainETHBridgeAdapter} from "@lattice/interfaces/crosschain/ISuperchainETHBridgeAdapter.sol";
import {ISuperchainETHBridge} from "@lattice/interfaces/external/optimism/ISuperchainETHBridge.sol";

/// @dev The canonical OP Stack `SuperchainETHBridge` predeploy (same address on every Superchain interop chain).
address constant SUPERCHAIN_ETH_BRIDGE = 0x4200000000000000000000000000000000000024;

/// @dev 0x832d7d61 is `type(ISuperchainETHBridgeAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x832d7d61), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ISUPERCHAINETHBRIDGEADAPTER_SLOT =
    0x3e08ed85f4544feff1f3f78c34d4e426159248bf51477cf7b08dde93bbe30744;

/// @title SuperchainETHBridgeAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Optimism (https://github.com/ethereum-optimism/optimism)
/// @notice Logic for the OP Stack `SuperchainETHBridge` interop adapter. A thin, OUTBOUND-ONLY payable
///         passthrough: `sendETH` forwards `msg.value` to the {SUPERCHAIN_ETH_BRIDGE} predeploy, which burns the
///         ETH, messages the destination via the `L2ToL2CrossDomainMessenger`, and force-sends it to the
///         recipient there.
/// @dev STATELESS — the predeploy is a compile-time constant, so there is NO ERC-7201 storage struct, no config,
///      no trusted-remote registry, and no admin surface (nothing to gate). The only init effect is registering
///      the {ISuperchainETHBridgeAdapter} ERC-165 id. No reentrancy guard: the adapter holds no ETH/state, the
///      call target is a trusted immutable predeploy, and it is outbound-only (the predeploy never calls back
///      into this diamond). ponytail: guardless because there is no reentrancy surface to guard.
library SuperchainETHBridgeAdapterLib {
    /// @notice Registers the {ISuperchainETHBridgeAdapter} ERC-165 id. Called inside the initializing window.
    function __SuperchainETHBridgeAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for {ISuperchainETHBridgeAdapter}.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ISUPERCHAINETHBRIDGEADAPTER_SLOT, true)
        }
    }

    /// @notice Bridges `msg.value` native ETH to `to` on Superchain chain `chainId` via the predeploy.
    /// @dev Reverts {InvalidRecipient} on a zero `to` (before the external call, though the predeploy also
    ///      rejects it) and {ZeroValue} on a zero `msg.value`. Forwards exactly `msg.value`; the diamond retains
    ///      no ETH afterward.
    function sendETH(address to, uint256 chainId) internal returns (bytes32 msgHash) {
        if (to == address(0)) revert ISuperchainETHBridgeAdapter.InvalidRecipient();
        if (msg.value == 0) revert ISuperchainETHBridgeAdapter.ZeroValue();
        // Reject the local chain early (the messenger reverts same-chain sends anyway) for a clear error + gas.
        if (chainId == block.chainid) revert ISuperchainETHBridgeAdapter.SameChain();

        msgHash = ISuperchainETHBridge(SUPERCHAIN_ETH_BRIDGE).sendETH{value: msg.value}(to, chainId);
        emit ISuperchainETHBridgeAdapter.ETHSent(msg.sender, to, msg.value, chainId, msgHash);
    }

    /// @notice The fixed `SuperchainETHBridge` predeploy this adapter forwards to.
    function bridge() internal pure returns (address) {
        return SUPERCHAIN_ETH_BRIDGE;
    }
}
