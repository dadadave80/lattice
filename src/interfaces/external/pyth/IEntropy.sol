// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IEntropy
/// @author Modified from Pyth (https://github.com/pyth-network/pyth-crosschain/blob/main/target_chains/ethereum/entropy_sdk/solidity/IEntropy.sol)
/// @notice Minimal interface for the Pyth Entropy on-demand randomness contract (commit/reveal).
/// @dev Vendored subset — do not add a pyth dependency. The Entropy contract fulfils a request by
///      calling `entropyCallback(uint64,address,bytes32)` back on the requester.
interface IEntropy {
    /// @notice Returns the address of the default randomness provider.
    function getDefaultProvider() external view returns (address provider);

    /// @notice Returns the fee (in wei) charged by `provider` for one request.
    /// @param provider The randomness provider to quote.
    /// @return feeAmount The required fee in wei.
    function getFee(address provider) external view returns (uint128 feeAmount);

    /// @notice Requests a random number with a callback, committing `userRandomNumber`.
    /// @dev Must be called with `msg.value >= getFee(provider)`. The provider fulfils by calling
    ///      `entropyCallback(sequenceNumber, provider, randomNumber)` on `msg.sender`.
    /// @param provider          The randomness provider to use.
    /// @param userRandomNumber  The caller's commitment to its half of the randomness.
    /// @return assignedSequenceNumber The sequence number identifying this request.
    function requestWithCallback(address provider, bytes32 userRandomNumber)
        external
        payable
        returns (uint64 assignedSequenceNumber);
}
