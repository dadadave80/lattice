// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {BridgeFungibleLib} from "@lattice/crosschain/libraries/BridgeFungibleLib.sol";
import {CrosschainLinkLib} from "@lattice/crosschain/libraries/CrosschainLinkLib.sol";
import {IBridgeFungible} from "@lattice/interfaces/IBridgeFungible.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.BridgeERC20")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant BRIDGE_ERC20_STORAGE_SLOT = 0x0e9006c16c4f5fe9e0e3215c8af601bd97024c6bebdfa0efe51c092276cd7c00;

/// @notice ERC-7201 namespaced storage for the ERC-20 custody bridge.
/// @custom:storage-location erc7201:lattice.storage.BridgeERC20
struct BridgeERC20Storage {
    /// @notice The bridged ERC-20 token (custody is taken on send, released on receive). APPEND-ONLY.
    address _token;
}

/// @title BridgeERC20Lib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin `BridgeERC20` v5.6.1.
/// @notice Custody bridge for legacy ERC-20s: locks tokens on send, releases them on receive. Acts as an
///         {IERC7786MessageHandler} co-mounted with a {CrosschainLink} facet.
library BridgeERC20Lib {
    function bridgeERC20Storage() internal pure returns (BridgeERC20Storage storage $) {
        assembly {
            $.slot := BRIDGE_ERC20_STORAGE_SLOT
        }
    }

    /// @notice Configures the bridged token and registers the IBridgeFungible ERC-165 interface.
    function __BridgeERC20_init(address token_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        if (token_ == address(0)) revert IBridgeFungible.BridgeZeroToken();
        bridgeERC20Storage()._token = token_;
        BridgeFungibleLib.registerInterface();
    }

    /// @notice The bridged ERC-20 token.
    function token() internal view returns (address) {
        return bridgeERC20Storage()._token;
    }

    /// @notice Locks `amount` of the token in custody and sends a bridge message to the destination chain.
    /// @param to     The full ERC-7930 interoperable address of the recipient (chain ref + address).
    /// @param amount The amount to lock here and release on the destination.
    function crosschainTransfer(bytes calldata to, uint256 amount) internal returns (bytes32 sendId) {
        ReentrancyGuardLib.nonReentrantBefore();
        address from = msg.sender;
        address tkn = bridgeERC20Storage()._token;

        (bytes memory chain, bytes memory toAddr) = BridgeFungibleLib.splitDestination(to);
        BridgeFungibleLib.pullExact(tkn, from, amount); // lock custody (rejects fee-on-transfer)

        sendId = CrosschainLinkLib.sendToCounterpart(
            chain, BridgeFungibleLib.buildPayload(from, toAddr, amount), new bytes[](0)
        );

        emit IBridgeFungible.CrosschainFungibleTransferSent(sendId, from, to, amount);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Releases custodied tokens to the inbound recipient. Callable only via the Diamond's own
    ///         authenticated `receiveMessage` dispatch (`msg.sender == address(this)`).
    /// @param receiveId The de-duplicated message id (replay already checked by {CrosschainLink}).
    /// @param payload   The tag-stripped inbound payload `abi.encode(from, toAddrBytes, amount)`.
    function processMessage(bytes32 receiveId, bytes calldata payload) internal {
        if (msg.sender != address(this)) revert IBridgeFungible.BridgeUnauthorizedCaller(msg.sender);
        ReentrancyGuardLib.nonReentrantBefore();

        (bytes memory from, address to, uint256 amount) = BridgeFungibleLib.decodeInbound(payload);
        BridgeFungibleLib.safeTransfer(bridgeERC20Storage()._token, to, amount); // release custody

        emit IBridgeFungible.CrosschainFungibleTransferReceived(receiveId, from, to, amount);
        ReentrancyGuardLib.nonReentrantAfter();
    }
}
