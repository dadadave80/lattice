// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IBridgeFungible} from "@lattice/interfaces/crosschain/IBridgeFungible.sol";
import {IERC7786MessageHandler} from "@lattice/interfaces/crosschain/IERC7786MessageHandler.sol";
import {ERC20CrosschainLib} from "@lattice/tokens/ERC20/libraries/ERC20CrosschainLib.sol";

/// @title ERC20Crosschain
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin `ERC20Crosschain` v5.6.1
///         (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/token/ERC20/extensions/ERC20Crosschain.sol)
/// @notice Self-bridging ERC-20 extension facet: `crosschainTransfer` burns the token's own supply and
///         sends a message; an inbound message mints it on the destination. Mount alongside {ERC20} +
///         {CrosschainLink}; register under {FUNGIBLE_BRIDGE_TAG}. No separate bridge or external token.
/// @dev Stateless delegator — logic in {ERC20CrosschainLib}, balances reuse the ERC20 storage.
///      `processMessage` is callable only via the Diamond's own `receiveMessage` dispatch
///      (`msg.sender == address(this)`). Payload format matches {BridgeFungible} (interop-compatible).
/// @custom:lattice-version 0.1.0
contract ERC20Crosschain is IBridgeFungible, IERC7786MessageHandler {
    /// @inheritdoc IBridgeFungible
    function crosschainTransfer(bytes calldata to, uint256 amount) external virtual override returns (bytes32 sendId) {
        return ERC20CrosschainLib.crosschainTransfer(to, amount);
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
        ERC20CrosschainLib.processMessage(receiveId, payload);
    }
}
