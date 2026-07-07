// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IMailbox} from "@lattice/interfaces/external/IMailbox.sol";
import {IMessageRecipient} from "@lattice/interfaces/external/IMessageRecipient.sol";

/// @title MockMailbox
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test fixture implementing the vendored {IMailbox}: records every `dispatch` arg verbatim (including
///         the RAW hook-metadata bytes for exact StandardHookMetadata packing assertions), pulls the fee the
///         way the real default-hook stack does (via `msg.value`), and returns a deterministic messageId.
///         `quoteDispatch` returns a settable fee. The `process` driver mirrors the upstream Mailbox's
///         one-shot `delivered` semantics (a second `process` of the same message reverts) and CALLS `handle`
///         on the recipient — so inbound tests run through the real facet exactly the way the Mailbox invokes
///         it.
contract MockMailbox is IMailbox {
    uint32 public localDomain = 1;
    uint256 public feeAmount = 0.01 ether;

    uint32 public lastDestinationDomain;
    bytes32 public lastRecipientAddress;
    bytes public lastBody;
    bytes public lastMetadata;
    uint256 public lastValue;
    uint256 public dispatches;

    mapping(bytes32 messageId => bool) public delivered;

    function setFee(uint256 fee) external {
        feeAmount = fee;
    }

    function setLocalDomain(uint32 domain) external {
        localDomain = domain;
    }

    function quoteDispatch(uint32, bytes32, bytes calldata) external view returns (uint256) {
        return feeAmount;
    }

    function quoteDispatch(uint32, bytes32, bytes calldata, bytes calldata) external view returns (uint256) {
        return feeAmount;
    }

    function dispatch(uint32 destinationDomain, bytes32 recipientAddress, bytes calldata messageBody)
        external
        payable
        returns (bytes32)
    {
        return _dispatch(destinationDomain, recipientAddress, messageBody, "");
    }

    function dispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata body,
        bytes calldata defaultHookMetadata
    ) external payable returns (bytes32) {
        return _dispatch(destinationDomain, recipientAddress, body, defaultHookMetadata);
    }

    function _dispatch(uint32 destinationDomain, bytes32 recipientAddress, bytes memory body, bytes memory metadata)
        internal
        returns (bytes32)
    {
        require(msg.value >= feeAmount, "fee");
        lastDestinationDomain = destinationDomain;
        lastRecipientAddress = recipientAddress;
        lastBody = body;
        lastMetadata = metadata;
        lastValue = msg.value;
        return keccak256(abi.encode("hyperlane-msg", ++dispatches));
    }

    /// @notice Inbound driver: mirrors the upstream Mailbox's one-shot semantics — the messageId (derived from
    ///         the full message tuple here) is marked `delivered` BEFORE the recipient call and a redelivery
    ///         reverts, exactly like `Mailbox.process`. Calls `handle` on `recipient` so the real facet path
    ///         runs (payable, forwarding any test-supplied value).
    function process(uint32 origin, bytes32 sender, address recipient, bytes calldata message)
        external
        payable
        returns (bytes32 messageId)
    {
        messageId = keccak256(abi.encode(origin, sender, recipient, message));
        require(!delivered[messageId], "Mailbox: already delivered");
        delivered[messageId] = true;
        IMessageRecipient(recipient).handle{value: msg.value}(origin, sender, message);
    }
}
