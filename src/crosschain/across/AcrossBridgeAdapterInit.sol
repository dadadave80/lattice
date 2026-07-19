// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AcrossBridgeAdapterLib} from "@lattice/crosschain/libraries/AcrossBridgeAdapterLib.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

/// @title AcrossBridgeAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an Across v3 token-bridge diamond — seeds the reentrancy guard (the deposit
///         and message-handling paths are `nonReentrant`) and wires the LOCAL chain's canonical SpokePool
///         (registering the IAcrossBridgeAdapter interface via ERC-165). NO AccessControl is seeded because the
///         adapter has no admin surface (Across chain ids are passed raw by callers; there is no domain table).
///         Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT open its own
///         pre/postInitializer; the `__*_init` guard passes because the window is already open). Reverts
///         `AcrossZeroAddress` if the SpokePool is zero.
contract AcrossBridgeAdapterInit {
    /// @notice Runs the reentrancy-guard + Across-adapter initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param spokePool The LOCAL chain's canonical Across v3 SpokePool.
    function init(address spokePool) external {
        ReentrancyGuardLib.__ReentrancyGuard_init();
        AcrossBridgeAdapterLib.__AcrossBridgeAdapter_init(spokePool);
    }
}
