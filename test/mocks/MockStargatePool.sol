// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MessagingFee, MessagingReceipt} from "@lattice/interfaces/external/layerzero/ILayerZeroEndpointV2.sol";
import {IStargate, OFTReceipt, SendParam, Ticket} from "@lattice/interfaces/external/layerzero/IStargate.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";

/// @title MockStargatePool
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test fixture implementing the minimal {IStargate} surface: records every `sendToken` argument
///         verbatim (all seven `SendParam` fields, the fee tuple, the refundAddress and `msg.value`, plus the
///         allowance it was granted), pulls `amountSentLD = amountLD` truncated to a configurable shared-
///         decimal `granularity` (default 1e12 — the real pools' dust-removal behavior) via `transferFrom`,
///         and returns receipts with a DETERMINISTIC guid (`keccak256(abi.encode(address(this), nonce))`) and
///         `amountReceivedLD = amountSentLD - poolFee` (the pools' fee deduction). `token()` serves the
///         adapter's fail-closed registration cross-check; the `quoteSend` native fee is settable.
/// @dev `setPullFunds(false)` simulates a pool that consumes NO allowance (the adapter must still reset the
///      approval to 0 and sweep everything back). Receipt values are reported regardless of the pull switch —
///      the adapter's sweep must key off REAL balances, never off receipt claims.
contract MockStargatePool is IStargate {
    address internal immutable _token;

    uint256 public granularity = 1e12;
    uint256 public poolFee;
    uint256 public nativeFee;
    bool public pullFunds = true;
    uint64 public nonce;

    uint32 public lastDstEid;
    bytes32 public lastTo;
    uint256 public lastAmountLD;
    uint256 public lastMinAmountLD;
    bytes public lastExtraOptions;
    bytes public lastComposeMsg;
    bytes public lastOftCmd;
    uint256 public lastNativeFee;
    uint256 public lastLzTokenFee;
    address public lastRefundAddress;
    uint256 public lastMsgValue;
    uint256 public allowanceSeen;
    uint256 public calls;

    constructor(address token_) {
        _token = token_;
    }

    function setGranularity(uint256 granularity_) external {
        granularity = granularity_;
    }

    function setPoolFee(uint256 poolFee_) external {
        poolFee = poolFee_;
    }

    function setNativeFee(uint256 nativeFee_) external {
        nativeFee = nativeFee_;
    }

    function setPullFunds(bool pull) external {
        pullFunds = pull;
    }

    /// @notice The guid the NEXT `sendToken` call will mint (deterministic — assertable up front).
    function nextGuid() external view returns (bytes32) {
        return keccak256(abi.encode(address(this), nonce + 1));
    }

    /// @inheritdoc IStargate
    function token() external view returns (address) {
        return _token;
    }

    /// @inheritdoc IStargate
    function quoteSend(SendParam calldata, bool) external view returns (MessagingFee memory) {
        return MessagingFee({nativeFee: nativeFee, lzTokenFee: 0});
    }

    /// @inheritdoc IStargate
    function sendToken(SendParam calldata sendParam, MessagingFee calldata fee, address refundAddress)
        external
        payable
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt, Ticket memory ticket)
    {
        lastDstEid = sendParam.dstEid;
        lastTo = sendParam.to;
        lastAmountLD = sendParam.amountLD;
        lastMinAmountLD = sendParam.minAmountLD;
        lastExtraOptions = sendParam.extraOptions;
        lastComposeMsg = sendParam.composeMsg;
        lastOftCmd = sendParam.oftCmd;
        lastNativeFee = fee.nativeFee;
        lastLzTokenFee = fee.lzTokenFee;
        lastRefundAddress = refundAddress;
        lastMsgValue = msg.value;
        allowanceSeen = IERC20(_token).allowance(msg.sender, address(this));
        ++calls;

        // Shared-decimal dust removal: the pool only ever debits amountLD truncated to the granularity.
        uint256 amountSentLD = sendParam.amountLD - (sendParam.amountLD % granularity);
        if (pullFunds && amountSentLD != 0) {
            IERC20(_token).transferFrom(msg.sender, address(this), amountSentLD);
        }

        uint64 n = ++nonce;
        msgReceipt = MessagingReceipt({guid: keccak256(abi.encode(address(this), n)), nonce: n, fee: fee});
        // Saturating fee deduction: a real pool would revert on slippage instead; the mock stays permissive
        // so conservation fuzzing can drive dust-sized amounts through.
        oftReceipt = OFTReceipt({
            amountSentLD: amountSentLD, amountReceivedLD: amountSentLD > poolFee ? amountSentLD - poolFee : 0
        });
        ticket = Ticket({ticketId: 0, passengerBytes: ""});
    }
}
