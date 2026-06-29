// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {BridgeFungibleLib} from "@lattice/crosschain/libraries/BridgeFungibleLib.sol";
import {CrosschainLinkLib} from "@lattice/crosschain/libraries/CrosschainLinkLib.sol";
import {IBridgeFungible} from "@lattice/interfaces/crosschain/IBridgeFungible.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";

/// @title ERC20CrosschainLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin `ERC20Crosschain` v5.6.1
///         (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/token/ERC20/extensions/ERC20Crosschain.sol).
/// @notice Self-bridging ERC-20: the token embeds the {BridgeFungible} logic, burning its OWN supply on
///         send and minting it on receive — no separate bridge contract or custodied/external token.
/// @dev Acts as an {IERC7786MessageHandler} co-mounted with {CrosschainLink} + {ERC20}; registers under the
///      shared {FUNGIBLE_BRIDGE_TAG} and reuses {IBridgeFungible} for ERC-165. No own storage (reuses the
///      ERC20 balances). No role is needed: `crosschainTransfer` burns the CALLER's own tokens, and the
///      inbound mint is gated by CrosschainLink's gateway/counterpart auth + the `address(this)` handler guard.
library ERC20CrosschainLib {
    /// @notice Registers the IBridgeFungible ERC-165 interface. Must be called in a pre/postInitializer block.
    function __ERC20Crosschain_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        BridgeFungibleLib.registerInterface();
    }

    /// @notice Burns `amount` of the caller's own supply and sends a bridge message to the destination.
    /// @param to     The full ERC-7930 interoperable address of the recipient (chain ref + address).
    /// @param amount The amount to burn here and mint on the destination.
    function crosschainTransfer(bytes calldata to, uint256 amount) internal returns (bytes32 sendId) {
        ReentrancyGuardLib.nonReentrantBefore();
        address from = msg.sender;

        (bytes memory chain, bytes memory toAddr) = BridgeFungibleLib.splitDestination(to);
        ERC20Lib._burn(from, amount); // burn own supply on the source chain

        sendId = CrosschainLinkLib.sendToCounterpart(
            chain, BridgeFungibleLib.buildPayload(from, toAddr, amount), new bytes[](0)
        );

        emit IBridgeFungible.CrosschainFungibleTransferSent(sendId, from, to, amount);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Mints `amount` of own supply to the inbound recipient. Callable only via the Diamond's own
    ///         authenticated `receiveMessage` dispatch (`msg.sender == address(this)`).
    /// @param receiveId The de-duplicated message id (replay already checked by {CrosschainLink}).
    /// @param payload   The tag-stripped inbound payload `abi.encode(from, toAddrBytes, amount)`.
    function processMessage(bytes32 receiveId, bytes calldata payload) internal {
        if (msg.sender != address(this)) revert IBridgeFungible.BridgeUnauthorizedCaller(msg.sender);
        ReentrancyGuardLib.nonReentrantBefore();

        (bytes memory from, address to, uint256 amount) = BridgeFungibleLib.decodeInbound(payload);
        ERC20Lib._mint(to, amount); // mint own supply on the destination chain

        emit IBridgeFungible.CrosschainFungibleTransferReceived(receiveId, from, to, amount);
        ReentrancyGuardLib.nonReentrantAfter();
    }
}
