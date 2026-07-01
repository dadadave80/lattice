// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SuperchainETHBridgeAdapterLib} from "@lattice/crosschain/libraries/SuperchainETHBridgeAdapterLib.sol";

/// @title SuperchainETHBridgeAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a `SuperchainETHBridge` interop adapter diamond — registers the
///         {ISuperchainETHBridgeAdapter} ERC-165 id. There is nothing else to seed: the adapter is stateless
///         (the predeploy is a compile-time constant), has no admin surface, and holds no funds. Delegatecalled
///         by {Diamond.initialize} inside the initializing window (so it must NOT open its own pre/postInitializer).
contract SuperchainETHBridgeAdapterInit {
    /// @notice Registers the adapter ERC-165 id. MUST be invoked via the diamond's `initialize` `_init` delegatecall.
    function init() external {
        SuperchainETHBridgeAdapterLib.__SuperchainETHBridgeAdapter_init();
    }
}
