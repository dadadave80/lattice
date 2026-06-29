// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IPythEntropyAdapter
/// @notice Interface for the PythEntropyAdapter Diamond facet — on-demand (commit/reveal) randomness.
/// @dev Request/track layer over Pyth Entropy. A request is caller-funded (the Entropy fee is quoted
///      via {getFee} and any excess `msg.value` is refunded); the provider fulfils via
///      {entropyCallback}, which is gated so only the configured Entropy contract may call it.
///      Consumer facets that inherit `PythEntropyAdapter` should override {entropyCallback} (calling
///      `super.entropyCallback` first) to act on the delivered randomness.
interface IPythEntropyAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when the Entropy configuration is updated.
    /// @param entropy  The Pyth Entropy contract.
    /// @param provider The randomness provider (or `address(0)` to use the default provider).
    event EntropyConfigSet(address entropy, address provider);

    /// @notice Emitted when a random number is requested.
    /// @param sequenceNumber The Entropy-assigned sequence number.
    /// @param userKey        The caller-supplied key associated with this request.
    event RandomNumberRequested(uint64 indexed sequenceNumber, bytes32 indexed userKey);

    /// @notice Emitted when the provider fulfils a request.
    /// @param sequenceNumber The Entropy-assigned sequence number.
    /// @param userKey        The caller-supplied key originally associated with this request.
    /// @param randomNumber   The delivered random number.
    event RandomNumberFulfilled(uint64 indexed sequenceNumber, bytes32 indexed userKey, bytes32 randomNumber);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice Entropy has not been configured (entropy contract address is zero).
    error EntropyNotConfigured();

    /// @notice `setConfig` was called with a zero Entropy contract address.
    error EntropyInvalidConfig();

    /// @notice `requestRandomNumber` was called with a zero `userKey`.
    /// @dev `bytes32(0)` is the sentinel used to detect a missing pending request.
    error EntropyInvalidUserKey();

    /// @notice `msg.value` was less than the Entropy fee.
    /// @param provided The value sent.
    /// @param required The required fee.
    error EntropyInsufficientFee(uint256 provided, uint256 required);

    /// @notice The excess-fee refund to the caller failed.
    error EntropyRefundFailed();

    /// @notice `entropyCallback` was called by an address other than the Entropy contract.
    /// @param caller The unauthorised caller.
    error EntropyOnlyEntropy(address caller);

    /// @notice The given sequence number has no pending entry.
    /// @param sequenceNumber The unknown sequence number.
    error EntropyRequestNotFound(uint64 sequenceNumber);

    // -------------------------------------------------------------------------
    //                                   Types
    // -------------------------------------------------------------------------

    /// @notice Pyth Entropy configuration.
    struct EntropyConfig {
        /// @notice The Pyth Entropy contract.
        address entropy;
        /// @notice The randomness provider (`address(0)` resolves to the Entropy default provider).
        address provider;
    }

    // -------------------------------------------------------------------------
    //                                   Reads
    // -------------------------------------------------------------------------

    /// @notice Returns the current Entropy configuration.
    function getConfig() external view returns (EntropyConfig memory);

    /// @notice Returns the fee (in wei) required for one request under the current config.
    function getFee() external view returns (uint256);

    /// @notice Returns the user key associated with a pending request.
    /// @param sequenceNumber The Entropy-assigned sequence number.
    /// @return The user-supplied key, or `bytes32(0)` if not found.
    function getUserKey(uint64 sequenceNumber) external view returns (bytes32);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Sets or replaces the Entropy configuration.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`. Reverts `EntropyInvalidConfig` if entropy is zero.
    /// @param config The new configuration.
    function setConfig(EntropyConfig calldata config) external;

    // -------------------------------------------------------------------------
    //                                Operations
    // -------------------------------------------------------------------------

    /// @notice Requests a random number, caller-funded with excess refunded.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE` and send `msg.value >= getFee()`.
    /// @param userKey          Arbitrary key the caller wants associated with this request.
    /// @param userRandomNumber The caller's commitment to its half of the randomness.
    /// @return sequenceNumber The Entropy-assigned sequence number.
    function requestRandomNumber(bytes32 userKey, bytes32 userRandomNumber)
        external
        payable
        returns (uint64 sequenceNumber);

    /// @notice Called by the Entropy contract to deliver a random number.
    /// @dev Verifies the caller is the configured Entropy contract, looks up the user key, clears the
    ///      pending entry, and emits `RandomNumberFulfilled`. Consumer facets should override this to
    ///      consume the randomness.
    /// @param sequence     The Entropy-assigned sequence number.
    /// @param provider     The provider that fulfilled the request.
    /// @param randomNumber The delivered random number.
    function entropyCallback(uint64 sequence, address provider, bytes32 randomNumber) external;
}
