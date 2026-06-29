// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IChainlinkVRF} from "@lattice/interfaces/oracles/IChainlinkVRF.sol";
import {ChainlinkVRFLib} from "@lattice/oracles/libraries/ChainlinkVRFLib.sol";

/// @title ChainlinkVRF
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Chainlink (https://github.com/smartcontractkit/chainlink-evm/blob/develop/contracts/src/v0.8/vrf/VRFConsumerBaseV2Plus.sol)
/// @notice Diamond facet for Chainlink VRF V2.5 subscription-funded random words.
/// @dev Stateless delegator — all logic and storage live in ChainlinkVRFLib.
///
///      This facet handles the request/track layer only.  Consumer facets that
///      inherit this contract should override `rawFulfillRandomWords` to act on
///      delivered randomness after calling `super.rawFulfillRandomWords`.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Chainlink
contract ChainlinkVRF is IChainlinkVRF {
    /// @inheritdoc IChainlinkVRF
    function getConfig() external view virtual override returns (VRFConfig memory) {
        return ChainlinkVRFLib.getConfig();
    }

    /// @inheritdoc IChainlinkVRF
    function getUserKey(uint256 vrfRequestId) external view virtual override returns (bytes32) {
        return ChainlinkVRFLib.getUserKey(vrfRequestId);
    }

    /// @inheritdoc IChainlinkVRF
    function setConfig(VRFConfig calldata config) external virtual override {
        ChainlinkVRFLib.setConfig(config);
    }

    /// @inheritdoc IChainlinkVRF
    function requestRandomWords(bytes32 userKey, uint32 numWords)
        external
        virtual
        override
        returns (uint256 vrfRequestId)
    {
        return ChainlinkVRFLib.requestRandomWords(userKey, numWords);
    }

    /// @inheritdoc IChainlinkVRF
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external virtual override {
        ChainlinkVRFLib.rawFulfillRandomWords(requestId, randomWords);
    }
}
