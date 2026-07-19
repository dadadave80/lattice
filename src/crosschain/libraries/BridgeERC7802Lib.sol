// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {BridgeFungibleLib} from "@lattice/crosschain/libraries/BridgeFungibleLib.sol";
import {CrosschainLinkLib} from "@lattice/crosschain/libraries/CrosschainLinkLib.sol";
import {IBridgeFungible} from "@lattice/interfaces/crosschain/IBridgeFungible.sol";
import {IERC7802} from "@lattice/interfaces/external/ercs/IERC7802.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.BridgeERC7802")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant BRIDGE_ERC7802_STORAGE_SLOT = 0x9d1b234db7644d1f76207933d92c2e89140027741ab600a4ff4b12a8d51e4b00;

/// @notice ERC-7201 namespaced storage for the ERC-7802 mint/burn bridge.
/// @custom:storage-location erc7201:lattice.storage.BridgeERC7802
struct BridgeERC7802Storage {
    /// @notice The bridged ERC-7802 token (burned on send, minted on receive). APPEND-ONLY.
    address _token;
}

/// @title BridgeERC7802Lib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin `BridgeERC7802` v5.6.1 (https://github.com/OpenZeppelin/openzeppelin-contracts).
/// @notice Mint/burn bridge for ERC-7802 tokens (approval-free): burns on send, mints on receive. Acts as
///         an {IERC7786MessageHandler} co-mounted with a {CrosschainLink} facet.
library BridgeERC7802Lib {
    function bridgeERC7802Storage() internal pure returns (BridgeERC7802Storage storage $) {
        assembly {
            $.slot := BRIDGE_ERC7802_STORAGE_SLOT
        }
    }

    /// @notice Configures the bridged token and registers the IBridgeFungible ERC-165 interface.
    function __BridgeERC7802_init(address token_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        if (token_ == address(0)) revert IBridgeFungible.BridgeZeroToken();
        bridgeERC7802Storage()._token = token_;
        BridgeFungibleLib.registerInterface();
    }

    /// @notice The bridged ERC-7802 token.
    function token() internal view returns (address) {
        return bridgeERC7802Storage()._token;
    }

    /// @notice Burns `amount` from the caller (ERC-7802) and sends a bridge message to the destination.
    /// @param to     The full ERC-7930 interoperable address of the recipient (chain ref + address).
    /// @param amount The amount to burn here and mint on the destination.
    function crosschainTransfer(bytes calldata to, uint256 amount) internal returns (bytes32 sendId) {
        ReentrancyGuardLib.nonReentrantBefore();
        address from = msg.sender;
        address tkn = bridgeERC7802Storage()._token;

        (bytes memory chain, bytes memory toAddr) = BridgeFungibleLib.splitDestination(to);
        IERC7802(tkn).crosschainBurn(from, amount); // burn on source

        sendId = CrosschainLinkLib.sendToCounterpart(
            chain, BridgeFungibleLib.buildPayload(from, toAddr, amount), new bytes[](0)
        );

        emit IBridgeFungible.CrosschainFungibleTransferSent(sendId, from, to, amount);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Mints tokens to the inbound recipient (ERC-7802). Callable only via the Diamond's own
    ///         authenticated `receiveMessage` dispatch (`msg.sender == address(this)`).
    /// @param receiveId The de-duplicated message id (replay already checked by {CrosschainLink}).
    /// @param payload   The tag-stripped inbound payload `abi.encode(from, toAddrBytes, amount)`.
    function processMessage(bytes32 receiveId, bytes calldata payload) internal {
        if (msg.sender != address(this)) revert IBridgeFungible.BridgeUnauthorizedCaller(msg.sender);
        ReentrancyGuardLib.nonReentrantBefore();

        (bytes memory from, address to, uint256 amount) = BridgeFungibleLib.decodeInbound(payload);
        IERC7802(bridgeERC7802Storage()._token).crosschainMint(to, amount); // mint on destination

        emit IBridgeFungible.CrosschainFungibleTransferReceived(receiveId, from, to, amount);
        ReentrancyGuardLib.nonReentrantAfter();
    }
}
