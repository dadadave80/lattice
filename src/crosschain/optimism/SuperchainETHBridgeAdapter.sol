// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SuperchainETHBridgeAdapterLib} from "@lattice/crosschain/optimism/SuperchainETHBridgeAdapterLib.sol";
import {ISuperchainETHBridgeAdapter} from "@lattice/interfaces/crosschain/ISuperchainETHBridgeAdapter.sol";

/// @title SuperchainETHBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Optimism (https://github.com/ethereum-optimism/optimism)
/// @notice OP Stack `SuperchainETHBridge` interop facet: `sendETH` forwards `msg.value` native ETH to the
///         canonical predeploy (`0x…0024`) to bridge it to another Superchain chain. OUTBOUND-ONLY native-ETH
///         interop — NOT the removed `SuperchainERC20` token bridge, and NOT an `IERC7786GatewaySource`.
/// @dev Stateless delegator — logic lives in {SuperchainETHBridgeAdapterLib}. The adapter holds no ETH/state and
///      has no admin surface (the predeploy address is a compile-time constant).
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Optimism
contract SuperchainETHBridgeAdapter is ISuperchainETHBridgeAdapter {
    /// @inheritdoc ISuperchainETHBridgeAdapter
    function sendETH(address to, uint256 chainId) external payable virtual returns (bytes32 msgHash) {
        return SuperchainETHBridgeAdapterLib.sendETH(to, chainId);
    }

    /// @inheritdoc ISuperchainETHBridgeAdapter
    function bridge() external pure virtual returns (address) {
        return SuperchainETHBridgeAdapterLib.bridge();
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect SuperchainETHBridgeAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `bridge()` 0xe78cea92
    ///      `sendETH(address,uint256)` 0x64a197f3
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"e78cea9264a197f3";
    }
}
