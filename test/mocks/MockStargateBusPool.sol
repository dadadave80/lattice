// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MockStargatePool} from "@lattice-test/mocks/MockStargatePool.sol";
import {BridgeFungibleLib} from "@lattice/crosschain/libraries/BridgeFungibleLib.sol";
import {MessagingFee, MessagingReceipt} from "@lattice/interfaces/external/layerzero/ILayerZeroEndpointV2.sol";
import {OFTReceipt, SendParam, Ticket} from "@lattice/interfaces/external/layerzero/IStargate.sol";
import {IReentrancyGuard} from "@lattice/interfaces/security/IReentrancyGuard.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";

/// @title MockStargateBusPool
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Stargate (https://github.com/stargate-protocol/stargate-v2)
/// @notice Independently authored queue fixture for the public pool ABI, not upstream queue implementation.
/// @dev Uses opaque 96-byte fixture passengers, not Stargate's wire codec. Enqueue has no GUID; a separate
///      direct drive validates an entire queued prefix and creates one. This proves adapter behavior only.
contract MockStargateBusPool is MockStargatePool {
    error MockBusUnavailable();
    error MockBusParameters();
    error MockBusFull();
    error MockBusSlippage();
    error MockBusFailure();
    error MockBusPrefix();

    uint256 public busFare = 0.002 ether;
    uint256 public driveFare = 0.001 ether;
    uint256 public maxQueued = 8;
    uint8 public receiptFailure;
    bool public failAfterPull;
    bool public busEnabled = true;
    mapping(uint32 => uint72) public nextTicket;
    mapping(uint32 => uint72) public nextTicketToDrive;
    mapping(uint32 => mapping(uint72 => bytes)) public passenger;
    address public callbackTarget;
    bytes public callbackData;
    bool public sawGuard;

    event MockBusDriven(uint32 indexed dstEid, uint72 firstTicket, uint256 passengers, bytes32 guid);

    constructor(address token_) MockStargatePool(token_) {}

    function setReceiptFailure(uint8 value) external {
        receiptFailure = value;
    }

    function setFailAfterPull(bool value) external {
        failAfterPull = value;
    }

    function setBusEnabled(bool value) external {
        busEnabled = value;
    }

    function setMaxQueued(uint256 value) external {
        maxQueued = value;
    }

    function setCallback(address target, bytes calldata data) external {
        callbackTarget = target;
        callbackData = data;
    }

    function quoteSend(SendParam calldata p, bool payInLzToken) public view override returns (MessagingFee memory) {
        if (p.oftCmd.length == 0) return super.quoteSend(p, payInLzToken);
        if (!busEnabled || busFare == 0) revert MockBusUnavailable();
        if (
            keccak256(p.oftCmd) != keccak256(hex"00") || p.extraOptions.length != 0 || p.composeMsg.length != 0
                || payInLzToken
        ) {
            revert MockBusParameters();
        }
        if (p.amountLD < granularity) revert MockBusParameters();
        return MessagingFee(busFare, 0);
    }

    function sendToken(SendParam calldata p, MessagingFee calldata fee, address refundAddress)
        public
        payable
        override
        returns (MessagingReceipt memory message, OFTReceipt memory receipt, Ticket memory ticket)
    {
        if (p.oftCmd.length == 0) return super.sendToken(p, fee, refundAddress);
        if (msg.value != quoteSend(p, false).nativeFee || fee.nativeFee != msg.value || fee.lzTokenFee != 0) {
            revert MockBusParameters();
        }
        if (nextTicket[p.dstEid] - nextTicketToDrive[p.dstEid] >= maxQueued) revert MockBusFull();
        lastDstEid = p.dstEid;
        lastTo = p.to;
        lastAmountLD = p.amountLD;
        lastMinAmountLD = p.minAmountLD;
        lastExtraOptions = p.extraOptions;
        lastComposeMsg = p.composeMsg;
        lastOftCmd = p.oftCmd;
        lastNativeFee = fee.nativeFee;
        lastLzTokenFee = fee.lzTokenFee;
        lastRefundAddress = refundAddress;
        lastMsgValue = msg.value;
        allowanceSeen = IERC20(_token).allowance(msg.sender, address(this));
        ++calls;
        uint256 sent = p.amountLD - p.amountLD % granularity;
        if (pullFunds) BridgeFungibleLib.pullExact(_token, msg.sender, sent);
        if (sent < poolFee || sent - poolFee < p.minAmountLD) revert MockBusSlippage();
        receipt = OFTReceipt(sent, sent - poolFee);
        uint72 id = nextTicket[p.dstEid]++;
        bytes memory data = abi.encode(id, p.to, receipt.amountReceivedLD);
        passenger[p.dstEid][id] = data;
        ticket = Ticket(id, data);
        message.fee = MessagingFee(busFare, 0);
        if (callbackTarget != address(0)) {
            (bool ok, bytes memory reason) = callbackTarget.call(callbackData);
            sawGuard = !ok
                && keccak256(reason)
                    == keccak256(abi.encodeWithSelector(IReentrancyGuard.ReentrancyGuardReentrantCall.selector));
            if (!sawGuard) revert MockBusFailure();
        }
        if (failAfterPull) revert MockBusFailure();
        if (receiptFailure == 1) message.guid = bytes32(uint256(1));
        if (receiptFailure == 2) message.nonce = 1;
        if (receiptFailure == 3) ticket.passengerBytes = "";
        if (receiptFailure == 4) message.fee.nativeFee -= 1;
        if (receiptFailure == 5) message.fee.lzTokenFee = 1;
    }

    function quoteDriveBus(uint32 eid, bytes calldata passengers) external view returns (MessagingFee memory) {
        _prefixCount(eid, passengers);
        return MessagingFee(driveFare, 0);
    }

    function driveBus(uint32 eid, bytes calldata passengers)
        external
        payable
        returns (MessagingReceipt memory message)
    {
        if (msg.value != driveFare) revert MockBusParameters();
        uint256 count = _prefixCount(eid, passengers);
        uint72 first = nextTicketToDrive[eid];
        nextTicketToDrive[eid] += uint72(count);
        message = MessagingReceipt(keccak256(abi.encode(address(this), ++nonce)), nonce, MessagingFee(msg.value, 0));
        emit MockBusDriven(eid, first, count, message.guid);
    }

    function _prefixCount(uint32 eid, bytes calldata passengers) private view returns (uint256 count) {
        bytes memory prefix;
        for (uint72 id = nextTicketToDrive[eid]; id < nextTicket[eid] && prefix.length < passengers.length; ++id) {
            prefix = bytes.concat(prefix, passenger[eid][id]);
            ++count;
        }
        if (count == 0 || keccak256(prefix) != keccak256(passengers)) revert MockBusPrefix();
    }
}
