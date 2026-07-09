// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IChainlinkVRF
/// @author Modified from Chainlink (https://github.com/smartcontractkit/chainlink-evm/blob/develop/contracts/src/v0.8/vrf/VRFConsumerBaseV2Plus.sol)
/// @notice Interface for the ChainlinkVRF Diamond facet.
/// @dev This module handles request tracking for Chainlink VRF V2.5
///      (subscription-funded).  The `rawFulfillRandomWords` entry point is called
///      by the coordinator and manages bookkeeping only; consumer facets that
///      inherit `ChainlinkVRF` should override it to act on the randomness.
interface IChainlinkVRF {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when the VRF configuration is updated.
    /// @param coordinator    Address of the VRF coordinator.
    /// @param subscriptionId Subscription ID funding the requests.
    /// @param keyHash        Key hash identifying the oracle's VRF public key.
    event VRFConfigSet(address coordinator, uint256 subscriptionId, bytes32 keyHash);

    /// @notice Emitted when random words are requested from the coordinator.
    /// @param vrfRequestId The coordinator-assigned request ID.
    /// @param userKey      The caller-supplied key associated with this request.
    /// @param numWords     The number of random words requested.
    event RandomWordsRequested(uint256 indexed vrfRequestId, bytes32 indexed userKey, uint32 numWords);

    /// @notice Emitted when the coordinator fulfils a request.
    /// @param vrfRequestId The coordinator-assigned request ID.
    /// @param userKey      The caller-supplied key originally associated with this request.
    event RandomWordsFulfilled(uint256 indexed vrfRequestId, bytes32 indexed userKey);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice VRF has not been configured (coordinator address is zero).
    error VRFNotConfigured();

    /// @notice `rawFulfillRandomWords` was called by an address other than the coordinator.
    /// @param caller The unauthorised caller.
    error VRFOnlyCoordinator(address caller);

    /// @notice The given VRF request ID has no pending entry.
    /// @param vrfRequestId The unknown request ID.
    error VRFRequestNotFound(uint256 vrfRequestId);

    /// @notice `setConfig` was called with an invalid configuration (zero coordinator,
    ///         zero subscription ID, or zero key hash).
    error VRFInvalidConfig();

    /// @notice `requestRandomWords` was called with a zero userKey.
    /// @dev `bytes32(0)` is the sentinel used by `rawFulfillRandomWords` to
    ///      detect a missing pending request. Allowing a zero userKey would make
    ///      the fulfillment callback indistinguishable from an unknown request ID.
    error VRFInvalidUserKey();

    // -------------------------------------------------------------------------
    //                                  Types
    // -------------------------------------------------------------------------

    /// @notice Full VRF subscription configuration.
    struct VRFConfig {
        /// @notice Address of the VRF coordinator.
        address coordinator;
        /// @notice Subscription ID funding requests.
        uint256 subscriptionId;
        /// @notice Key hash identifying the oracle's VRF public key.
        bytes32 keyHash;
        /// @notice Minimum confirmations before the oracle responds.
        uint16 requestConfirmations;
        /// @notice Gas limit for the fulfillment callback.
        uint32 callbackGasLimit;
    }

    // -------------------------------------------------------------------------
    //                                   Reads
    // -------------------------------------------------------------------------

    /// @notice Returns the current VRF configuration.
    function getConfig() external view returns (VRFConfig memory);

    /// @notice Returns the user key associated with a pending VRF request.
    /// @param vrfRequestId The coordinator-assigned request ID.
    /// @return The user-supplied key, or `bytes32(0)` if not found.
    function getUserKey(uint256 vrfRequestId) external view returns (bytes32);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Sets or replaces the VRF configuration.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`.
    ///      Reverts `VRFInvalidConfig` if coordinator is zero, subscriptionId is
    ///      zero, or keyHash is zero.
    /// @param config The new VRF configuration.
    function setConfig(VRFConfig calldata config) external;

    // -------------------------------------------------------------------------
    //                                Operations
    // -------------------------------------------------------------------------

    /// @notice Requests random words from the VRF coordinator.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`.
    ///      Stores the `userKey` against the returned `vrfRequestId` so the
    ///      fulfilment callback can look it up.
    /// @param userKey  Arbitrary key the caller wants associated with this request.
    /// @param numWords Number of random words to request.
    /// @return vrfRequestId The coordinator-assigned request ID.
    function requestRandomWords(bytes32 userKey, uint32 numWords) external returns (uint256 vrfRequestId);

    /// @notice Called by the VRF coordinator to deliver random words.
    /// @dev Verifies the caller is the configured coordinator, looks up the user key,
    ///      clears the pending entry, and emits `RandomWordsFulfilled`.
    ///      Consumer facets should override this function to consume the randomness.
    /// @param requestId  The coordinator-assigned request ID.
    /// @param randomWords The generated random words.
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external;
}
