// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CrosschainLinkLib} from "@lattice/crosschain/libraries/CrosschainLinkLib.sol";
import {ICrosschainLink} from "@lattice/interfaces/ICrosschainLink.sol";
import {IERC7786Recipient} from "@lattice/interfaces/external/IERC7786.sol";

/// @title CrosschainLink
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin `CrosschainLinked` + `ERC7786Recipient` v5.6.1
///         (https://github.com/OpenZeppelin/openzeppelin-contracts/tree/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/crosschain)
/// @notice Diamond facet that owns the single ERC-7786 `receiveMessage` selector. It authenticates the
///         calling gateway + source against a per-chain link registry, de-duplicates `receiveId`, and
///         routes the message to a handler registered for the payload's leading 4-byte tag. Also exposes
///         the send path (`sendMessage`) to a registered counterpart.
/// @dev Stateless delegator — all logic and storage live in {CrosschainLinkLib}. Consumers inherit this
///      facet and add AccessControl + an initializer that calls `CrosschainLinkLib.__CrosschainLink_init`.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin
contract CrosschainLink is IERC7786Recipient, ICrosschainLink {
    /// @inheritdoc IERC7786Recipient
    function receiveMessage(bytes32 receiveId, bytes calldata sender, bytes calldata payload)
        external
        payable
        virtual
        override
        returns (bytes4)
    {
        return CrosschainLinkLib.receiveMessage(receiveId, sender, payload);
    }

    /// @inheritdoc ICrosschainLink
    function getLink(bytes calldata chain)
        external
        view
        virtual
        override
        returns (address gateway, bytes memory counterpart)
    {
        return CrosschainLinkLib.getLink(chain);
    }

    /// @inheritdoc ICrosschainLink
    function getHandler(bytes4 tag) external view virtual override returns (address handler) {
        return CrosschainLinkLib.getHandler(tag);
    }

    /// @inheritdoc ICrosschainLink
    function isProcessed(address gateway, bytes32 receiveId) external view virtual override returns (bool) {
        return CrosschainLinkLib.isProcessed(gateway, receiveId);
    }

    /// @inheritdoc ICrosschainLink
    function setLink(address gateway, bytes calldata counterpart, bool allowOverride) external virtual override {
        CrosschainLinkLib.setLink(gateway, counterpart, allowOverride);
    }

    /// @inheritdoc ICrosschainLink
    function setHandler(bytes4 tag, address handler) external virtual override {
        CrosschainLinkLib.setHandler(tag, handler);
    }

    /// @inheritdoc ICrosschainLink
    function sendMessage(bytes calldata chain, bytes calldata payload, bytes[] calldata attributes)
        external
        virtual
        override
        returns (bytes32 sendId)
    {
        return CrosschainLinkLib.sendMessage(chain, payload, attributes);
    }
}
