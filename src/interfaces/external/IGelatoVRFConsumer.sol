// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IGelatoVRFConsumer
/// @author Modified from Gelato (https://github.com/gelatodigital/vrf-contracts/blob/main/contracts/IGelatoVRFConsumer.sol)
/// @notice Callback interface for Gelato VRF (drand-backed) consumers.
/// @dev Vendored — do not add a gelato dependency. The consumer emits `RequestedRandomness`; Gelato's
///      dedicated operator fulfils by calling `fulfillRandomness`. There is no on-chain fee
///      (it is paid off-chain via Gelato 1Balance).
interface IGelatoVRFConsumer {
    /// @notice Emitted to request randomness for a given drand `round`.
    /// @param round The drand round whose beacon will seed the randomness.
    /// @param data  Opaque request payload (`abi.encode(round, abi.encode(requestId, extraData))`).
    event RequestedRandomness(uint256 round, bytes data);

    /// @notice Called by the Gelato operator to deliver randomness.
    /// @param randomness    The drand-derived randomness for the requested round.
    /// @param dataWithRound The opaque payload originally emitted in `RequestedRandomness`.
    function fulfillRandomness(uint256 randomness, bytes calldata dataWithRound) external;
}
