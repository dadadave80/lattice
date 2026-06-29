// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BridgeERC7802Lib} from "@lattice/crosschain/libraries/BridgeERC7802Lib.sol";
import {IBridgeFungible} from "@lattice/interfaces/crosschain/IBridgeFungible.sol";
import {IERC7786MessageHandler} from "@lattice/interfaces/crosschain/IERC7786MessageHandler.sol";

/// @title BridgeERC7802
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin `BridgeERC7802` v5.6.1
///         (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/crosschain/bridges/BridgeERC7802.sol)
/// @notice Mint/burn bridge facet for ERC-7802 tokens: burns on `crosschainTransfer`, mints on an inbound
///         message. Registered as a handler on a co-mounted {CrosschainLink} facet.
/// @dev Stateless delegator — logic/storage live in {BridgeERC7802Lib}. `processMessage` is callable only
///      via the Diamond's own authenticated `receiveMessage` dispatch (`msg.sender == address(this)`).
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin
contract BridgeERC7802 is IBridgeFungible, IERC7786MessageHandler {
    /// @inheritdoc IBridgeFungible
    function crosschainTransfer(bytes calldata to, uint256 amount) external virtual override returns (bytes32 sendId) {
        return BridgeERC7802Lib.crosschainTransfer(to, amount);
    }

    /// @inheritdoc IERC7786MessageHandler
    function processMessage(
        bytes32 receiveId,
        bytes calldata,
        /*sender*/
        bytes calldata payload
    )
        external
        virtual
        override
    {
        BridgeERC7802Lib.processMessage(receiveId, payload);
    }

    /// @notice The bridged ERC-7802 token.
    function token() external view virtual returns (address) {
        return BridgeERC7802Lib.token();
    }
}
