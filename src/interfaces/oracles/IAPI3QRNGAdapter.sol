// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAPI3QRNGAdapter
/// @notice Interface for the API3QRNGAdapter Diamond facet — quantum randomness via API3 Airnode RRP.
/// @dev Request/track layer over the Airnode Request-Response Protocol. The diamond is its own sponsor
///      (self-sponsoring): {setSelfSponsorship} registers it with the RRP, then {requestRandomNumber}
///      makes a full request. The Airnode fulfils via {fulfillRandomNumber}, gated so only the
///      configured Airnode RRP contract may call it (`onlyAirnodeRrp`). Consumer facets that inherit
///      `API3QRNGAdapter` should override {fulfillRandomNumber} (calling `super.fulfillRandomNumber`
///      first) to act on the randomness.
interface IAPI3QRNGAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when the QRNG configuration is updated.
    /// @param airnodeRrp   The Airnode RRP contract.
    /// @param airnode      The Airnode serving requests.
    /// @param endpointId   The QRNG endpoint identifier.
    /// @param sponsorWallet The wallet paying for fulfilment gas.
    event QRNGConfigSet(address airnodeRrp, address airnode, bytes32 endpointId, address sponsorWallet);

    /// @notice Emitted when this contract's self-sponsorship status is changed.
    /// @param status True if now self-sponsored, false if revoked.
    event QRNGSelfSponsorshipSet(bool status);

    /// @notice Emitted when a random number is requested.
    /// @param requestId The RRP-assigned request ID.
    /// @param userKey   The caller-supplied key associated with this request.
    event RandomNumberRequested(bytes32 indexed requestId, bytes32 indexed userKey);

    /// @notice Emitted when the Airnode fulfils a request.
    /// @param requestId    The RRP-assigned request ID.
    /// @param userKey      The caller-supplied key originally associated with this request.
    /// @param randomNumber The delivered quantum random number.
    event RandomNumberFulfilled(bytes32 indexed requestId, bytes32 indexed userKey, uint256 randomNumber);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice QRNG has not been configured (Airnode RRP address is zero).
    error QRNGNotConfigured();

    /// @notice `setConfig` was called with a zero Airnode RRP, zero Airnode, zero endpoint, or zero wallet.
    error QRNGInvalidConfig();

    /// @notice `requestRandomNumber` was called with a zero `userKey`.
    /// @dev `bytes32(0)` is the sentinel used to detect a missing pending request.
    error QRNGInvalidUserKey();

    /// @notice `fulfillRandomNumber` was called by an address other than the Airnode RRP contract.
    /// @param caller The unauthorised caller.
    error QRNGOnlyAirnodeRrp(address caller);

    /// @notice The given request ID has no pending entry.
    /// @param requestId The unknown request ID.
    error QRNGRequestNotFound(bytes32 requestId);

    // -------------------------------------------------------------------------
    //                                   Types
    // -------------------------------------------------------------------------

    /// @notice API3 QRNG configuration. The sponsor is always this contract (self-sponsoring).
    struct QRNGConfig {
        /// @notice The Airnode RRP contract.
        address airnodeRrp;
        /// @notice The Airnode serving requests.
        address airnode;
        /// @notice The QRNG endpoint identifier.
        bytes32 endpointId;
        /// @notice The wallet (derived from this sponsor) paying for fulfilment gas.
        address sponsorWallet;
    }

    // -------------------------------------------------------------------------
    //                                   Reads
    // -------------------------------------------------------------------------

    /// @notice Returns the current QRNG configuration.
    function getConfig() external view returns (QRNGConfig memory);

    /// @notice Returns the user key associated with a pending request.
    /// @param requestId The RRP-assigned request ID.
    /// @return The user-supplied key, or `bytes32(0)` if not found.
    function getUserKey(bytes32 requestId) external view returns (bytes32);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Sets or replaces the QRNG configuration.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`. Reverts `QRNGInvalidConfig` on any zero field.
    /// @param config The new configuration.
    function setConfig(QRNGConfig calldata config) external;

    /// @notice Registers (or revokes) this contract as its own sponsor with the Airnode RRP.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`. A full request only succeeds while self-sponsored.
    /// @param status True to self-sponsor, false to revoke.
    function setSelfSponsorship(bool status) external;

    // -------------------------------------------------------------------------
    //                                Operations
    // -------------------------------------------------------------------------

    /// @notice Requests a quantum random number via the Airnode RRP.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param userKey Arbitrary key the caller wants associated with this request.
    /// @return requestId The RRP-assigned request ID.
    function requestRandomNumber(bytes32 userKey) external returns (bytes32 requestId);

    /// @notice Called by the Airnode RRP to deliver the random number.
    /// @dev Verifies the caller is the configured Airnode RRP, looks up the user key, clears the
    ///      pending entry, decodes the random number, and emits `RandomNumberFulfilled`. Consumer
    ///      facets should override this to consume the randomness.
    /// @param requestId The RRP-assigned request ID.
    /// @param data      The ABI-encoded random number (`abi.encode(uint256)`).
    function fulfillRandomNumber(bytes32 requestId, bytes calldata data) external;
}
