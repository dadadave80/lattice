// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IChainlinkVRF} from "@lattice/interfaces/IChainlinkVRF.sol";
import {IVRFCoordinatorV2Plus} from "@lattice/interfaces/external/IVRFCoordinatorV2Plus.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ChainlinkVRF")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant CHAINLINK_VRF_STORAGE_SLOT = 0x296a09c3f1dda7c7057a0d3e9cfd88b1666f0f2ebdcbdc2f576bbcf22db0d200;

/// @dev 0xed74ccf3 is `type(IChainlinkVRF).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xed74ccf3), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ICHAINLINKVRF_SLOT = 0x5e805972aa7ebffe06f2b61cc9d80c103d549fa32d030cc2918893026547c07e;

/// @notice ERC-7201 namespaced storage for ChainlinkVRF.
/// @custom:storage-location erc7201:lattice.storage.ChainlinkVRF
struct ChainlinkVRFStorage {
    address _coordinator;
    uint256 _subscriptionId;
    bytes32 _keyHash;
    uint16 _requestConfirmations;
    uint32 _callbackGasLimit;
    mapping(uint256 vrfRequestId => bytes32 userKey) _pendingRequests;
}

/// @title ChainlinkVRFLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Chainlink (https://github.com/smartcontractkit/chainlink-evm/blob/develop/contracts/src/v0.8/vrf/VRFConsumerBaseV2Plus.sol)
/// @notice Library that wraps Chainlink VRF V2.5 (subscription-funded) random
///         word requests.  This is the request/track layer only — fulfillment
///         bookkeeping is handled here, but consumer facets inheriting
///         `ChainlinkVRF` should override `rawFulfillRandomWords` (or add a
///         follow-up hook) to actually consume the delivered randomness.
library ChainlinkVRFLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the ERC-7201 storage struct for ChainlinkVRF.
    function chainlinkVRFStorage() internal pure returns (ChainlinkVRFStorage storage $) {
        assembly {
            $.slot := CHAINLINK_VRF_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IChainlinkVRF ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __ChainlinkVRF_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for IChainlinkVRF.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ICHAINLINKVRF_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the current VRF configuration.
    function getConfig() internal view returns (IChainlinkVRF.VRFConfig memory config) {
        ChainlinkVRFStorage storage $ = chainlinkVRFStorage();
        config = IChainlinkVRF.VRFConfig({
            coordinator: $._coordinator,
            subscriptionId: $._subscriptionId,
            keyHash: $._keyHash,
            requestConfirmations: $._requestConfirmations,
            callbackGasLimit: $._callbackGasLimit
        });
    }

    /// @notice Returns the user key associated with a pending VRF request.
    /// @param vrfRequestId The coordinator-assigned request ID.
    function getUserKey(uint256 vrfRequestId) internal view returns (bytes32) {
        return chainlinkVRFStorage()._pendingRequests[vrfRequestId];
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets or replaces the VRF configuration.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    ///      Reverts `VRFInvalidConfig` if coordinator is zero, subscriptionId is
    ///      zero, or keyHash is zero.
    /// @param config The new VRF configuration.
    function setConfig(IChainlinkVRF.VRFConfig calldata config) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (config.coordinator == address(0) || config.subscriptionId == 0 || config.keyHash == bytes32(0)) {
            revert IChainlinkVRF.VRFInvalidConfig();
        }
        ChainlinkVRFStorage storage $ = chainlinkVRFStorage();
        $._coordinator = config.coordinator;
        $._subscriptionId = config.subscriptionId;
        $._keyHash = config.keyHash;
        $._requestConfirmations = config.requestConfirmations;
        $._callbackGasLimit = config.callbackGasLimit;
        emit IChainlinkVRF.VRFConfigSet(config.coordinator, config.subscriptionId, config.keyHash);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Requests random words from the VRF coordinator.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    ///      Stores the `userKey` against the returned `vrfRequestId` so the
    ///      fulfillment callback can look it up.
    ///      Reverts `VRFNotConfigured` if coordinator has not been set.
    /// @param userKey  Arbitrary key the caller wants associated with this request.
    /// @param numWords Number of random words to request.
    /// @return vrfRequestId The coordinator-assigned request ID.
    function requestRandomWords(bytes32 userKey, uint32 numWords) internal returns (uint256 vrfRequestId) {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        // bytes32(0) is the sentinel used by rawFulfillRandomWords to detect a
        // missing pending request. Reject it here to prevent silent sentinel collision.
        if (userKey == bytes32(0)) revert IChainlinkVRF.VRFInvalidUserKey();
        ChainlinkVRFStorage storage $ = chainlinkVRFStorage();
        if ($._coordinator == address(0)) revert IChainlinkVRF.VRFNotConfigured();

        IVRFCoordinatorV2Plus.RandomWordsRequest memory req = IVRFCoordinatorV2Plus.RandomWordsRequest({
            keyHash: $._keyHash,
            subId: $._subscriptionId,
            requestConfirmations: $._requestConfirmations,
            callbackGasLimit: $._callbackGasLimit,
            numWords: numWords,
            extraArgs: bytes("")
        });

        vrfRequestId = IVRFCoordinatorV2Plus($._coordinator).requestRandomWords(req);
        $._pendingRequests[vrfRequestId] = userKey;
        emit IChainlinkVRF.RandomWordsRequested(vrfRequestId, userKey, numWords);
    }

    /// @notice Called by the VRF coordinator to deliver random words.
    /// @dev Verifies the caller is the configured VRF coordinator by its address (`msg.sender`),
    ///      looks up the user key, clears the pending entry, and emits `RandomWordsFulfilled`.
    ///
    ///      NOTE: This function only manages bookkeeping.  Consumer facets that
    ///      inherit `ChainlinkVRF` should override `rawFulfillRandomWords` (or
    ///      provide a follow-up hook) to act on the delivered randomness.
    /// @param requestId   The coordinator-assigned request ID.
    /// @param randomWords The array of random words (unused at this layer).
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal {
        ChainlinkVRFStorage storage $ = chainlinkVRFStorage();

        // Authenticate the VRF coordinator by its address.
        if (msg.sender != $._coordinator) revert IChainlinkVRF.VRFOnlyCoordinator(msg.sender);

        bytes32 userKey = $._pendingRequests[requestId];
        if (userKey == bytes32(0)) revert IChainlinkVRF.VRFRequestNotFound(requestId);

        delete $._pendingRequests[requestId];
        emit IChainlinkVRF.RandomWordsFulfilled(requestId, userKey);

        // randomWords is passed in but not consumed at this layer.
        // Silence the unused-variable warning.
        (randomWords);
    }
}
