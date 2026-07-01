// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {CCTPBridgeAdapterLib} from "@lattice/crosschain/libraries/CCTPBridgeAdapterLib.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

/// @title CCTPBridgeAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Circle CCTP v2 USDC token-bridge diamond — seeds AccessControl (so the
///         chain-domain and per-domain config setters are `DEFAULT_ADMIN_ROLE`-gated), the reentrancy guard
///         (the burn path is `nonReentrant`), and wires the deployed CCTP TokenMessenger + MessageTransmitter +
///         USDC (registering the ICCTPBridgeAdapter interface via ERC-165). Delegatecalled by
///         {Diamond.initialize} inside the initializing window (so it must NOT open its own pre/postInitializer;
///         each `__*_init` guard passes because the window is already open). Reverts `CCTPZeroAddress` if any of
///         the three CCTP addresses is zero.
contract CCTPBridgeAdapterInit {
    /// @notice Runs the access-control + reentrancy-guard + CCTP-adapter initializers. MUST be invoked via the
    ///         diamond's `initialize` `_init` delegatecall.
    /// @param admin              The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param tokenMessenger     The deployed CCTP v2 `TokenMessengerV2` (burn side).
    /// @param messageTransmitter The deployed CCTP v2 `MessageTransmitterV2` (receive/mint side).
    /// @param usdc               The deployed USDC token bridged by CCTP.
    function init(address admin, address tokenMessenger, address messageTransmitter, address usdc) external {
        AccessControlLib.__AccessControl_init(admin);
        ReentrancyGuardLib.__ReentrancyGuard_init();
        CCTPBridgeAdapterLib.__CCTPBridgeAdapter_init(tokenMessenger, messageTransmitter, usdc);
    }
}
