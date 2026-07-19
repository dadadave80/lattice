// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IChainlinkVRF} from "@lattice/interfaces/oracles/IChainlinkVRF.sol";
import {ChainlinkVRFLib} from "@lattice/oracles/chainlink/ChainlinkVRFLib.sol";

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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ChainlinkVRF methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `getConfig()` 0xc3f909d4
    ///      `getUserKey(uint256)` 0xdd1e2651
    ///      `rawFulfillRandomWords(uint256,uint256[])` 0x1fe543e3
    ///      `requestRandomWords(bytes32,uint32)` 0x5eff05e5
    ///      `setConfig((address,uint256,bytes32,uint16,uint32))` 0xb289a570
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"c3f909d4dd1e26511fe543e35eff05e5b289a570";
    }
}
