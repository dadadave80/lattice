// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Client} from "@lattice/interfaces/external/CCIPClient.sol";

/// @title IAny2EVMMessageReceiver (Chainlink CCIP) — vendored subset
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Minimal vendored subset of Chainlink CCIP's `IAny2EVMMessageReceiver` (interfaceId `0x85572ffb`),
///         the destination-side delivery callback the router invokes.
/// @dev Verified verbatim against `smartcontractkit/chainlink-ccip` @ `main` commit `828897a` (2026-06-24):
///      `chains/evm/contracts/interfaces/IAny2EVMMessageReceiver.sol`. The router calls
///      `supportsInterface(0x85572ffb)` BEFORE delivery; if it returns false the router silently delivers only
///      tokens and drops the message. Implementations MUST restrict `ccipReceive` to the router.
/// @custom:lattice-source Chainlink
interface IAny2EVMMessageReceiver {
    /// @notice Called by the CCIP router to deliver a cross-chain message.
    function ccipReceive(Client.Any2EVMMessage calldata message) external;
}
