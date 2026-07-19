// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {BridgeERC20Lib} from "@lattice/crosschain/libraries/BridgeERC20Lib.sol";
import {CrosschainLinkLib} from "@lattice/crosschain/libraries/CrosschainLinkLib.sol";

/// @title BridgeERC20Init
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a custody-bridge diamond over a legacy ERC-20 — seeds AccessControl, the
///         reentrancy guard (the lock/release path is `nonReentrant`), the {CrosschainLink} messaging registry,
///         and configures the bridged token. Delegatecalled by {Diamond.initialize} inside the initializing
///         window (so it must NOT open its own pre/postInitializer; each `__*_init` guard passes because the
///         window is already open). Reverts `BridgeZeroToken` if `token` is the zero address.
contract BridgeERC20Init {
    /// @notice Runs the access-control + reentrancy-guard + crosschain-link + bridge initializers. MUST be
    ///         invoked via the diamond's `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the link/handler registry).
    /// @param token The legacy ERC-20 token custodied by the bridge.
    function init(address admin, address token) external {
        AccessControlLib.__AccessControl_init(admin);
        CrosschainLinkLib.__CrosschainLink_init();
        BridgeERC20Lib.__BridgeERC20_init(token);
    }
}
