// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SuperchainETHBridgeAdapterLib} from "@lattice/crosschain/optimism/SuperchainETHBridgeAdapterLib.sol";

/// @title SuperchainETHBridgeAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a `SuperchainETHBridge` interop adapter diamond — registers the
///         {ISuperchainETHBridgeAdapter} ERC-165 id. There is nothing else to seed: the adapter is stateless
///         (the predeploy is a compile-time constant), has no admin surface, and holds no funds. Delegatecalled
///         by {Lattice.initialize} inside the initializing window (so it must NOT open its own pre/postInitializer).
/// @custom:lattice-kind step
contract SuperchainETHBridgeAdapterInit {
    /// @notice Registers the adapter ERC-165 id. MUST be invoked via the diamond's `initialize` `_init` delegatecall.
    /// @custom:lattice-initializes SuperchainETHBridgeAdapter;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-param none;
    /// @custom:lattice-registers-interfaces
    function init() external {
        SuperchainETHBridgeAdapterLib.__SuperchainETHBridgeAdapter_init();
    }
}
