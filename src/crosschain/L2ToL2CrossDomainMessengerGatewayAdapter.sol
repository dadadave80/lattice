// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    L2ToL2CrossDomainMessengerGatewayAdapterLib
} from "@lattice/crosschain/libraries/L2ToL2CrossDomainMessengerGatewayAdapterLib.sol";
import {
    IL2ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice/interfaces/crosschain/IL2ToL2CrossDomainMessengerGatewayAdapter.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/IERC7786.sol";

/// @title L2ToL2CrossDomainMessengerGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice ERC-7786 cross-chain gateway facet over the OP Superchain `L2ToL2CrossDomainMessenger` predeploy.
///         `sendMessage` dispatches a message via the messenger (no fee); `receiveCrossChainMessage` is the
///         messenger-invoked delivery callback on the destination adapter. EVM (Superchain) chains only.
/// @dev Stateless delegator — logic/storage live in {L2ToL2CrossDomainMessengerGatewayAdapterLib}. The messenger
///      routes by BARE EVM `chainId` (no eid/selector map); the trusted-remote registry is a single
///      `chainId ⇒ remoteAdapter` mapping. INVERTED INBOUND AUTH: the messenger CALLs `receiveCrossChainMessage`
///      as the `_target` during `relayMessage`, so `msg.sender` is the messenger predeploy — the remote gateway
///      is authenticated out-of-band via `crossDomainMessageContext`, not from `msg.sender`.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Optimism
contract L2ToL2CrossDomainMessengerGatewayAdapter is IERC7786GatewaySource, IL2ToL2CrossDomainMessengerGatewayAdapter {
    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        external
        payable
        virtual
        returns (bytes32)
    {
        return L2ToL2CrossDomainMessengerGatewayAdapterLib.sendMessage(recipient, payload, attributes);
    }

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 selector) external pure virtual returns (bool) {
        return L2ToL2CrossDomainMessengerGatewayAdapterLib.supportsAttribute(selector);
    }

    /// @inheritdoc IL2ToL2CrossDomainMessengerGatewayAdapter
    function receiveCrossChainMessage(
        bytes calldata sender,
        bytes calldata recipient,
        bytes calldata payload,
        uint256 nonce
    ) external virtual {
        L2ToL2CrossDomainMessengerGatewayAdapterLib.receiveCrossChainMessage(sender, recipient, payload, nonce);
    }

    /// @inheritdoc IL2ToL2CrossDomainMessengerGatewayAdapter
    function messenger() external view virtual returns (address) {
        return L2ToL2CrossDomainMessengerGatewayAdapterLib.messenger();
    }

    /// @inheritdoc IL2ToL2CrossDomainMessengerGatewayAdapter
    function getRemoteAdapter(uint256 chainId) external view virtual returns (address) {
        return L2ToL2CrossDomainMessengerGatewayAdapterLib.getRemoteAdapter(chainId);
    }

    /// @inheritdoc IL2ToL2CrossDomainMessengerGatewayAdapter
    function registerRemoteAdapter(uint256 chainId, address remoteAdapter) external virtual {
        L2ToL2CrossDomainMessengerGatewayAdapterLib.registerRemoteAdapter(chainId, remoteAdapter);
    }
}
