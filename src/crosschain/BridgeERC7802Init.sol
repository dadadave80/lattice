// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {BridgeERC7802Lib} from "@lattice/crosschain/libraries/BridgeERC7802Lib.sol";
import {CrosschainLinkLib} from "@lattice/crosschain/libraries/CrosschainLinkLib.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

/// @title BridgeERC7802Init
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a mint/burn-bridge diamond over an ERC-7802 token — seeds AccessControl, the
///         reentrancy guard (the burn/mint path is `nonReentrant`), the {CrosschainLink} messaging registry, and
///         configures the bridged token. Delegatecalled by {Diamond.initialize} inside the initializing window
///         (so it must NOT open its own pre/postInitializer; each `__*_init` guard passes because the window is
///         already open). Reverts `BridgeZeroToken` if `token` is the zero address.
contract BridgeERC7802Init {
    /// @notice Runs the access-control + reentrancy-guard + crosschain-link + bridge initializers. MUST be
    ///         invoked via the diamond's `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the link/handler registry).
    /// @param token The ERC-7802 token minted/burned by the bridge.
    function init(address admin, address token) external {
        AccessControlLib.__AccessControl_init(admin);
        ReentrancyGuardLib.__ReentrancyGuard_init();
        CrosschainLinkLib.__CrosschainLink_init();
        BridgeERC7802Lib.__BridgeERC7802_init(token);
    }
}
