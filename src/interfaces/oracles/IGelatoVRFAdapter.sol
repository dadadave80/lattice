// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IGelatoVRFAdapter
/// @notice Interface for the GelatoVRFAdapter Diamond facet — drand-backed randomness (no on-chain fee).
/// @dev Request/track layer over Gelato VRF. A request emits `RequestedRandomness` (the Gelato
///      `IGelatoVRFConsumer` event) for the dedicated operator to pick up; the operator fulfils via
///      {fulfillRandomness}, which is gated so only the configured operator may call it. The delivered
///      randomness is domain-separated per request before being surfaced. Consumer facets that inherit
///      `GelatoVRFAdapter` should override {fulfillRandomness} (calling `super.fulfillRandomness`
///      first) to act on the randomness.
interface IGelatoVRFAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when the dedicated operator is updated.
    /// @param operator The Gelato dedicated operator allowed to fulfil requests.
    event GelatoVRFOperatorSet(address operator);

    /// @notice Emitted (in addition to the Gelato `RequestedRandomness` event) when randomness is requested.
    /// @param requestId The adapter-assigned request ID.
    /// @param userKey   The caller-supplied key associated with this request.
    /// @param round     The drand round whose beacon will seed the randomness.
    event RandomnessRequested(uint256 indexed requestId, bytes32 indexed userKey, uint256 round);

    /// @notice Emitted when the operator fulfils a request.
    /// @param requestId  The adapter-assigned request ID.
    /// @param userKey    The caller-supplied key originally associated with this request.
    /// @param randomness The domain-separated randomness delivered for this request.
    event RandomnessFulfilled(uint256 indexed requestId, bytes32 indexed userKey, uint256 randomness);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice The dedicated operator has not been configured (operator address is zero).
    error GelatoVRFNotConfigured();

    /// @notice `setOperator` was called with a zero operator address.
    error GelatoVRFInvalidOperator();

    /// @notice `requestRandomness` was called with a zero `userKey`.
    /// @dev `bytes32(0)` is the sentinel used to detect a missing pending request.
    error GelatoVRFInvalidUserKey();

    /// @notice `fulfillRandomness` was called by an address other than the dedicated operator.
    /// @param caller The unauthorised caller.
    error GelatoVRFOnlyOperator(address caller);

    /// @notice The given request ID has no pending entry (already fulfilled or never requested).
    /// @param requestId The unknown request ID.
    error GelatoVRFRequestNotFound(uint256 requestId);

    // -------------------------------------------------------------------------
    //                                   Reads
    // -------------------------------------------------------------------------

    /// @notice Returns the configured dedicated operator.
    function getOperator() external view returns (address);

    /// @notice Returns the user key associated with a pending request.
    /// @param requestId The adapter-assigned request ID.
    /// @return The user-supplied key, or `bytes32(0)` if not found.
    function getUserKey(uint256 requestId) external view returns (bytes32);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Sets or replaces the dedicated operator.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`. Reverts `GelatoVRFInvalidOperator` if zero.
    /// @param operator The new dedicated operator.
    function setOperator(address operator) external;

    // -------------------------------------------------------------------------
    //                                Operations
    // -------------------------------------------------------------------------

    /// @notice Requests randomness from Gelato VRF.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`. Emits `RequestedRandomness` for the operator.
    /// @param userKey Arbitrary key the caller wants associated with this request.
    /// @return requestId The adapter-assigned request ID.
    function requestRandomness(bytes32 userKey) external returns (uint256 requestId);

    /// @notice Called by the dedicated operator to deliver randomness.
    /// @dev Verifies the caller is the configured operator, decodes the request, domain-separates the
    ///      randomness, clears the pending entry, and emits `RandomnessFulfilled`. Consumer facets
    ///      should override this to consume the randomness.
    /// @param randomness    The drand-derived randomness for the requested round.
    /// @param dataWithRound The opaque payload originally emitted in `RequestedRandomness`.
    function fulfillRandomness(uint256 randomness, bytes calldata dataWithRound) external;
}
