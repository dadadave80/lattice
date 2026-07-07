// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MessagingFee, MessagingReceipt} from "@lattice/interfaces/external/ILayerZeroEndpointV2.sol";

/// @title IStargate (Stargate v2 pool / OFT send surface) — minimal ABI-equivalent interface
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Vendored minimal struct subset of LayerZero's `IOFT` (https://github.com/LayerZero-Labs/LayerZero-v2). Upstream is MIT.
/// @author ABI-equivalent interface authored fresh from Stargate v2's public ABI (https://github.com/stargate-protocol/stargate-v2) — upstream sources are BUSL-1.1 and were NOT copied.
/// @notice Minimal Stargate v2 surface the Lattice adapter dispatches through: the 3-tuple `sendToken`
///         (Stargate's OFT `send` variant that additionally returns the bus {Ticket}), the `quoteSend` fee
///         quote, and the `token` read (the pooled ERC-20 a Pool wraps). `IStargate` extends LayerZero's
///         `IOFT` upstream; only the members this adapter calls are declared here.
/// @dev LICENSING SPLIT (deliberate): the `SendParam` / `OFTReceipt` structs are vendored VERBATIM from
///      LayerZero-v2's MIT `IOFT.sol` (`packages/layerzero-v2/evm/oapp/contracts/oft/interfaces/IOFT.sol`);
///      the shared `MessagingFee` / `MessagingReceipt` structs are imported from the repo's existing MIT
///      {ILayerZeroEndpointV2} vendored subset. The `IStargate` interface itself and the {Ticket} struct are
///      AUTHORED FRESH against Stargate v2's public ABI, because `stargate-protocol/stargate-v2` sources
///      (including `src/interfaces/IStargate.sol`) are BUSL-1.1 — no upstream Stargate text is copied. ABIs
///      are not copyrightable expression; signatures match the canonical deployment EXACTLY. Do NOT add a
///      `stargate-v2` dependency.
/// @custom:lattice-source Stargate

/// @notice Token parameters of an OFT `send`/`sendToken`: destination endpoint id, 32-byte recipient, the
///         amount and slippage floor in LOCAL decimals, plus the executor `extraOptions`, optional
///         `composeMsg` (destination `lzCompose` payload) and `oftCmd` (Stargate: empty = taxi, non-empty =
///         bus).
struct SendParam {
    uint32 dstEid; // Destination endpoint ID.
    bytes32 to; // Recipient address.
    uint256 amountLD; // Amount to send in local decimals.
    uint256 minAmountLD; // Minimum amount to send in local decimals.
    bytes extraOptions; // Additional options supplied by the caller to be used in the LayerZero message.
    bytes composeMsg; // The composed message for the send() operation.
    bytes oftCmd; // The OFT command to be executed, unused in default OFT implementations.
}

/// @notice OFT receipt: `amountSentLD` is the amount ACTUALLY debited from the sender (OFTs truncate
///         `amountLD` to shared decimals — dust removal), `amountReceivedLD` what the destination credits
///         (Stargate pools additionally deduct pool fees here).
struct OFTReceipt {
    uint256 amountSentLD; // Amount of tokens ACTUALLY debited from the sender in local decimals.
    // @dev In non-default implementations, the amountReceivedLD COULD differ from this value.
    uint256 amountReceivedLD; // Amount of tokens to be received on the remote side.
}

/// @notice Stargate bus-ride ticket returned by `sendToken`. Empty (`ticketId` 0, no passenger bytes) in
///         taxi mode (empty `oftCmd`); populated only for bus-mode sends, which this adapter does not issue.
/// @dev Authored fresh (field names/types per the public ABI) — needed only to declare `sendToken`'s exact
///      3-tuple return type.
struct Ticket {
    uint72 ticketId;
    bytes passengerBytes;
}

/// @notice The Stargate v2 send surface (Pool or OFT — both expose the same ABI).
interface IStargate {
    /// @notice Sends `_sendParam.amountLD` of the pooled/OFT token to `_sendParam.dstEid`. Same as the OFT
    ///         `send` but additionally returns the bus {Ticket} (empty in taxi mode).
    /// @param _sendParam     The send parameters (see {SendParam}).
    /// @param _fee           The caller-supplied fee (`nativeFee` must accompany the call as `msg.value`).
    /// @param _refundAddress Receiver of any excess native fee on THIS chain.
    function sendToken(SendParam calldata _sendParam, MessagingFee calldata _fee, address _refundAddress)
        external
        payable
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt, Ticket memory ticket);

    /// @notice Quotes the LayerZero messaging fee for `_sendParam` (`_payInLzToken` selects the fee leg).
    function quoteSend(SendParam calldata _sendParam, bool _payInLzToken) external view returns (MessagingFee memory);

    /// @notice The underlying ERC-20 this Stargate instance moves (the pooled asset for a Pool).
    function token() external view returns (address);
}
