// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    L1ToL2CrossDomainMessengerGatewayAdapterLib
} from "@lattice/crosschain/libraries/L1ToL2CrossDomainMessengerGatewayAdapterLib.sol";
import {
    IL1ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice/interfaces/crosschain/IL1ToL2CrossDomainMessengerGatewayAdapter.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/IERC7786.sol";

/// @title L1ToL2CrossDomainMessengerGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice ERC-7786 cross-chain gateway facet over the canonical OP Stack L1<->L2 `CrossDomainMessenger` predeploy.
///         `sendMessage` dispatches a message via the messenger (no fee); `receiveCrossChainMessage` is the
///         messenger-invoked delivery callback on the destination adapter. Carries deposits (L1->L2) and
///         withdrawals (L2->L1); direction-agnostic (identical adapter on both domains).
/// @dev Stateless delegator — logic/storage live in {L1ToL2CrossDomainMessengerGatewayAdapterLib}. A canonical
///      L1<->L2 pair has exactly ONE other domain, so the trusted remote is a SINGLE fixed counterpart
///      `(counterpartChainId, counterpartAdapter)` (NOT a `chainId => remote` map). INVERTED INBOUND AUTH: the
///      messenger CALLs `receiveCrossChainMessage` as the `_target` during relay, so `msg.sender` is the L2
///      messenger predeploy — the counterpart gateway is authenticated out-of-band via `xDomainMessageSender`,
///      not from `msg.sender`.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Optimism
contract L1ToL2CrossDomainMessengerGatewayAdapter is IERC7786GatewaySource, IL1ToL2CrossDomainMessengerGatewayAdapter {
    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        external
        payable
        virtual
        returns (bytes32)
    {
        return L1ToL2CrossDomainMessengerGatewayAdapterLib.sendMessage(recipient, payload, attributes);
    }

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 selector) external pure virtual returns (bool) {
        return L1ToL2CrossDomainMessengerGatewayAdapterLib.supportsAttribute(selector);
    }

    /// @inheritdoc IL1ToL2CrossDomainMessengerGatewayAdapter
    function receiveCrossChainMessage(
        bytes calldata sender,
        bytes calldata recipient,
        bytes calldata payload,
        uint256 nonce
    ) external virtual {
        L1ToL2CrossDomainMessengerGatewayAdapterLib.receiveCrossChainMessage(sender, recipient, payload, nonce);
    }

    /// @inheritdoc IL1ToL2CrossDomainMessengerGatewayAdapter
    function messenger() external view virtual returns (address) {
        return L1ToL2CrossDomainMessengerGatewayAdapterLib.messenger();
    }

    /// @inheritdoc IL1ToL2CrossDomainMessengerGatewayAdapter
    function counterpartChainId() external view virtual returns (uint256) {
        return L1ToL2CrossDomainMessengerGatewayAdapterLib.counterpartChainId();
    }

    /// @inheritdoc IL1ToL2CrossDomainMessengerGatewayAdapter
    function counterpartAdapter() external view virtual returns (address) {
        return L1ToL2CrossDomainMessengerGatewayAdapterLib.counterpartAdapter();
    }

    /// @inheritdoc IL1ToL2CrossDomainMessengerGatewayAdapter
    function minGasLimit() external view virtual returns (uint32) {
        return L1ToL2CrossDomainMessengerGatewayAdapterLib.minGasLimit();
    }

    /// @inheritdoc IL1ToL2CrossDomainMessengerGatewayAdapter
    function setCounterpart(uint256 chainId, address adapter) external virtual {
        L1ToL2CrossDomainMessengerGatewayAdapterLib.setCounterpart(chainId, adapter);
    }

    /// @inheritdoc IL1ToL2CrossDomainMessengerGatewayAdapter
    function setMinGasLimit(uint32 newMinGasLimit) external virtual {
        L1ToL2CrossDomainMessengerGatewayAdapterLib.setMinGasLimit(newMinGasLimit);
    }
}
