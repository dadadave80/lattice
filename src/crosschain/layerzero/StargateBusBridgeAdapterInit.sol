// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StargateBusBridgeAdapterLib} from "@lattice/crosschain/layerzero/StargateBusBridgeAdapterLib.sol";

/// @title StargateBusBridgeAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Registers the optional bus interface in a guarded initialization window; grants no authority.
/// @dev An existing configured taxi diamond may add the companion and invoke this via ReinitMultiInit.
/// @custom:lattice-kind step
contract StargateBusBridgeAdapterInit {
    /// @custom:lattice-initializes StargateBusBridgeAdapter;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-param none;
    /// @custom:lattice-registers-interfaces
    function init() external {
        StargateBusBridgeAdapterLib.__StargateBusBridgeAdapter_init();
    }
}
