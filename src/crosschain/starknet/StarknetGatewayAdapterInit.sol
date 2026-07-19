// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {StarknetGatewayAdapterLib} from "@lattice/crosschain/starknet/StarknetGatewayAdapterLib.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

/// @title StarknetGatewayAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Starknet L1 <-> L2 connector diamond — seeds AccessControl (so the L2
///         handler / trusted-sender setters are `DEFAULT_ADMIN_ROLE`-gated), the reentrancy guard (the
///         send/cancel/consume paths are `nonReentrant`), and wires the Starknet core + expected ERC-7930
///         chain reference (registering the IStarknetGatewayAdapter interface via ERC-165). Delegatecalled by
///         {Diamond.initialize} inside the initializing window (so it must NOT open its own pre/postInitializer;
///         each `__*_init` guard passes because the window is already open). Reverts `StarknetZeroAddress` on a
///         zero core, `StarknetEmptyChainReference` on an empty chain reference.
contract StarknetGatewayAdapterInit {
    /// @notice Runs the access-control + reentrancy-guard + Starknet-adapter initializers. MUST be invoked via
    ///         the diamond's `initialize` `_init` delegatecall.
    /// @param admin                  The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param starknetCore           The Starknet core (`StarknetMessaging`) contract on this chain.
    /// @param expectedChainReference The ERC-7930 chain reference this adapter accepts (UTF-8 chain-id string,
    ///                               e.g. `SN_MAIN` = `0x534e5f4d41494e`).
    function init(address admin, address starknetCore, bytes calldata expectedChainReference) external {
        AccessControlLib.__AccessControl_init(admin);
        ReentrancyGuardLib.__ReentrancyGuard_init();
        StarknetGatewayAdapterLib.__StarknetGatewayAdapter_init(starknetCore, expectedChainReference);
    }
}
