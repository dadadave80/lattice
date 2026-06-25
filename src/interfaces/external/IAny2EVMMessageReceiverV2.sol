// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAny2EVMMessageReceiver} from "@lattice/interfaces/external/IAny2EVMMessageReceiver.sol";

/// @title IAny2EVMMessageReceiverV2 (Chainlink CCIP) — vendored subset
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice CCV (Cross-Chain Verifier) extension of `IAny2EVMMessageReceiver` (interfaceId `0x9eabab2b`). On
///         CCV-enabled lanes the CCIP router queries `getCCVsAndFinalityConfig` to learn the verifiers a
///         receiver requires and the finality it accepts for inbound messages from a given source chain.
/// @dev Verified against `smartcontractkit/chainlink-ccip` @ `main` commit `828897a` (2026-06-24):
///      `chains/evm/contracts/interfaces/IAny2EVMMessageReceiverV2.sol`. interfaceId = V1 (`0x85572ffb`) XOR
///      `getCCVsAndFinalityConfig` (`0x1bfc84d0`) = `0x9eabab2b`. `allowedFinalityConfig == bytes4(0)` means
///      require full finality (the safe default).
/// @custom:lattice-source Chainlink
interface IAny2EVMMessageReceiverV2 is IAny2EVMMessageReceiver {
    /// @notice Returns the receiver's required + optional Cross-Chain Verifiers, the optional-CCV threshold,
    ///         and the allowed finality config for messages arriving from `sourceChainSelector`.
    function getCCVsAndFinalityConfig(uint64 sourceChainSelector, bytes calldata sender)
        external
        view
        returns (
            address[] memory requiredCCVs,
            address[] memory optionalCCVs,
            uint8 optionalThreshold,
            bytes4 allowedFinalityConfig
        );
}
