// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StargateBusBridgeAdapterLib} from "@lattice/crosschain/layerzero/StargateBusBridgeAdapterLib.sol";
import {IStargateBridgeAdapter} from "@lattice/interfaces/crosschain/IStargateBridgeAdapter.sol";
import {IStargateBusBridgeAdapter} from "@lattice/interfaces/crosschain/IStargateBusBridgeAdapter.sol";

/// @title StargateBusBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Stargate (https://github.com/stargate-protocol/stargate-v2)
/// @notice Optional stateless bus-enqueue companion; the original Stargate facet remains taxi-only.
/// @dev Shared configuration, no new namespace. Success reports a queue ticket, never a delivery GUID.
/// @custom:lattice-source Stargate
/// @custom:lattice-requires StargateBridgeAdapter convention shared-pool-and-eid-configuration-surface;
/// @custom:lattice-family none
/// @custom:lattice-owns none;
/// @custom:lattice-touches lattice.storage.StargateBridgeAdapter;
/// @custom:lattice-touches slot:0x8000000000ab143c06;
/// @custom:lattice-seam none;
/// @custom:lattice-init StargateBusBridgeAdapterInit
contract StargateBusBridgeAdapter is IStargateBusBridgeAdapter {
    /// @inheritdoc IStargateBusBridgeAdapter
    function quoteBusFee(IStargateBridgeAdapter.SendTokenParams calldata p) external view returns (uint256 nativeFee) {
        return StargateBusBridgeAdapterLib.quoteBusFee(p);
    }

    /// @inheritdoc IStargateBusBridgeAdapter
    function sendTokenBus(IStargateBridgeAdapter.SendTokenParams calldata p)
        external
        payable
        returns (uint72 ticketId, bytes memory passengerBytes, uint256 amountSentLD, uint256 amountReceivedLD)
    {
        return StargateBusBridgeAdapterLib.sendTokenBus(p);
    }

    /// @notice ERC-8153 export of the two companion selectors; excludes exportSelectors itself.
    function exportSelectors() external pure returns (bytes memory) {
        return hex"6dc4af12fe204e08";
    }
}
