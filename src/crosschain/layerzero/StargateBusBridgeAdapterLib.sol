// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StargateBridgeAdapterLib} from "@lattice/crosschain/layerzero/StargateBridgeAdapterLib.sol";
import {BridgeFungibleLib} from "@lattice/crosschain/libraries/BridgeFungibleLib.sol";
import {AdapterBaseLib} from "@lattice/defi/libraries/AdapterBaseLib.sol";
import {IStargateBridgeAdapter} from "@lattice/interfaces/crosschain/IStargateBridgeAdapter.sol";
import {IStargateBusBridgeAdapter} from "@lattice/interfaces/crosschain/IStargateBusBridgeAdapter.sol";
import {MessagingFee, MessagingReceipt} from "@lattice/interfaces/external/layerzero/ILayerZeroEndpointV2.sol";
import {IStargate, OFTReceipt, SendParam, Ticket} from "@lattice/interfaces/external/layerzero/IStargate.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @dev 0x93e4e11a is `type(IStargateBusBridgeAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x93e4e11a), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ISTARGATEBUSBRIDGEADAPTER_SLOT =
    0xc3f7c678c88a9c7c360b718bb3391b1779ca4fbd1a2bf4d65479d1695e0fbd50;

/// @title StargateBusBridgeAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Stargate (https://github.com/stargate-protocol/stargate-v2)
/// @notice Original bus-enqueue integration against the pinned Stargate public ABI; no upstream queue code.
/// @dev Owns no storage. Shares the taxi adapter's trusted pool/eid configuration and diamond-global guard.
///      Canonical mode is one zero byte; options/compose stay empty. No local ticket ledger or driver exists.
library StargateBusBridgeAdapterLib {
    function __StargateBusBridgeAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ISTARGATEBUSBRIDGEADAPTER_SLOT, true)
        }
    }

    function quoteBusFee(IStargateBridgeAdapter.SendTokenParams calldata p) internal view returns (uint256 nativeFee) {
        (address pool, SendParam memory sendParam) = _buildBusParam(p);
        return IStargate(pool).quoteSend(sendParam, false).nativeFee;
    }

    function sendTokenBus(IStargateBridgeAdapter.SendTokenParams calldata p)
        internal
        returns (uint72 ticketId, bytes memory passengerBytes, uint256 amountSentLD, uint256 amountReceivedLD)
    {
        ReentrancyGuardLib.nonReentrantBefore();
        (address pool, SendParam memory sendParam) = _buildBusParam(p);
        uint256 fare = IStargate(pool).quoteSend(sendParam, false).nativeFee;
        if (msg.value != fare) revert IStargateBusBridgeAdapter.StargateBusFeeMismatch(fare, msg.value);

        uint256 snapshot = AdapterBaseLib.balanceOfSelf(p.token);
        BridgeFungibleLib.pullExact(p.token, msg.sender, p.amountLD);
        AdapterBaseLib.forceApprove(p.token, pool, p.amountLD);
        (OFTReceipt memory receipt, Ticket memory ticket) = _callPool(pool, sendParam, fare);
        AdapterBaseLib.forceApprove(p.token, pool, 0);
        uint256 leftover = AdapterBaseLib.balanceOfSelf(p.token) - snapshot;
        if (leftover != 0) AdapterBaseLib.transferHonest(p.token, msg.sender, leftover);

        _emitQueued(p, sendParam.to, ticket, receipt);
        ReentrancyGuardLib.nonReentrantAfter();
        return (ticket.ticketId, ticket.passengerBytes, receipt.amountSentLD, receipt.amountReceivedLD);
    }

    function _buildBusParam(IStargateBridgeAdapter.SendTokenParams calldata p)
        private
        view
        returns (address pool, SendParam memory sendParam)
    {
        (pool, sendParam) = StargateBridgeAdapterLib._buildSendParam(p);
        sendParam.oftCmd = hex"00";
    }

    function _callPool(address pool, SendParam memory sendParam, uint256 fare)
        private
        returns (OFTReceipt memory receipt, Ticket memory ticket)
    {
        MessagingReceipt memory message;
        (message, receipt, ticket) = IStargate(pool).sendToken{value: msg.value}(
            sendParam, MessagingFee({nativeFee: msg.value, lzTokenFee: 0}), msg.sender
        );
        if (message.guid != bytes32(0) || message.nonce != 0 || ticket.passengerBytes.length == 0) {
            revert IStargateBusBridgeAdapter.StargateBusUnexpectedReceipt(
                message.guid, message.nonce, ticket.passengerBytes.length
            );
        }
        if (message.fee.nativeFee != fare || message.fee.lzTokenFee != 0) {
            revert IStargateBusBridgeAdapter.StargateBusUnexpectedFare(
                fare, message.fee.nativeFee, message.fee.lzTokenFee
            );
        }
    }

    function _emitQueued(
        IStargateBridgeAdapter.SendTokenParams calldata p,
        bytes32 recipient,
        Ticket memory ticket,
        OFTReceipt memory receipt
    ) private {
        emit IStargateBusBridgeAdapter.StargateBusQueued(
            msg.sender,
            p.token,
            p.destinationChainId,
            ticket.ticketId,
            ticket.passengerBytes,
            receipt.amountSentLD,
            receipt.amountReceivedLD,
            recipient
        );
    }
}
