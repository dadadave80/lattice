// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IVRFCoordinatorV2Plus
/// @author Modified from Chainlink (https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol)
/// @notice Minimal interface for Chainlink VRF Coordinator V2.5 (subscription-funded).
/// @dev Vendored subset — do not add a chainlink dependency.
interface IVRFCoordinatorV2Plus {
    /// @notice Parameters for a random words request.
    struct RandomWordsRequest {
        /// @notice The key hash identifying the oracle's VRF public key.
        bytes32 keyHash;
        /// @notice The subscription ID used to fund the request.
        uint256 subId;
        /// @notice Minimum number of confirmations before the oracle responds.
        uint16 requestConfirmations;
        /// @notice Gas limit for the fulfillment callback.
        uint32 callbackGasLimit;
        /// @notice Number of random words to request.
        uint32 numWords;
        /// @notice Extra arguments (e.g. LINK payment flag encoded via VRFV2PlusClient).
        bytes extraArgs;
    }

    /// @notice Requests random words from the VRF coordinator.
    /// @param req The request parameters.
    /// @return requestId The ID assigned to this request.
    function requestRandomWords(RandomWordsRequest calldata req) external returns (uint256 requestId);
}
