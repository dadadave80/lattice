// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IHederaPrngAdapter
/// @author Modified from hiero-ledger/hiero-contracts (https://github.com/hiero-ledger/hiero-contracts)
/// @notice Interface for the HederaPrngAdapter Diamond facet — consensus-derived randomness from the PRNG
///         system contract (HIP-351), the Hedera-native counterpart of the VRF / Entropy adapters.
/// @dev Unlike VRF, the seed is available synchronously in the same transaction (no request / fulfil round
///      trip) and is derived from the previous transaction record's running hash — not manipulable by the
///      caller, but visible to the node that orders the transaction. Not a `view`: the network records the
///      draw as a child transaction.
interface IHederaPrngAdapter {
    /// @notice Emitted on every draw.
    event HederaSeedDrawn(bytes32 seed, address indexed requester);

    /// @notice The PRNG system contract halted.
    error HederaPrngCallFailed();

    /// @notice `lo` must be less than `hi`.
    error HederaPrngInvalidRange(uint32 lo, uint32 hi);

    /// @notice Draws a fresh 32-byte seed.
    function drawSeed() external returns (bytes32 seed);

    /// @notice Draws a seed and reduces it to a number in `[lo, hi)`.
    function drawInRange(uint32 lo, uint32 hi) external returns (uint32 number);
}
