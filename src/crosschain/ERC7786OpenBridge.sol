// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC7786OpenBridgeLib} from "@lattice/crosschain/libraries/ERC7786OpenBridgeLib.sol";
import {IERC7786OpenBridge} from "@lattice/interfaces/crosschain/IERC7786OpenBridge.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/IERC7786.sol";

/// @title ERC7786OpenBridge
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin community-contracts `ERC7786OpenBridge` (https://github.com/OpenZeppelin/openzeppelin-community-contracts, commit f7e5f08)
///         (https://github.com/OpenZeppelin/openzeppelin-community-contracts/blob/f7e5f08e8fd42023084eb41f4a992d7be897b915/contracts/crosschain/ERC7786OpenBridge.sol)
/// @notice N-of-M ERC-7786 aggregator facet: `sendMessage` fans a message out across M gateways, and
///         `receiveMessage` delivers to the recipient once N independent gateways have attested it. It is
///         both an `IERC7786GatewaySource` (send) and an `IERC7786Recipient` (the gateways deliver to it).
/// @dev Stateless delegator — logic/storage live in {ERC7786OpenBridgeLib}. OZ's `Ownable` → AccessControl
///      and `EnumerableSet`/state → ERC-7201 storage. (Pausable/sweep from upstream are omitted.)
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin
contract ERC7786OpenBridge is IERC7786GatewaySource, IERC7786Recipient, IERC7786OpenBridge {
    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        external
        payable
        virtual
        returns (bytes32)
    {
        return ERC7786OpenBridgeLib.sendMessage(recipient, payload, attributes);
    }

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 selector) external pure virtual returns (bool) {
        return ERC7786OpenBridgeLib.supportsAttribute(selector);
    }

    /// @inheritdoc IERC7786Recipient
    function receiveMessage(bytes32 receiveId, bytes calldata sender, bytes calldata payload)
        external
        payable
        virtual
        returns (bytes4)
    {
        return ERC7786OpenBridgeLib.receiveMessage(receiveId, sender, payload);
    }

    /// @inheritdoc IERC7786OpenBridge
    function getGateways() external view virtual returns (address[] memory) {
        return ERC7786OpenBridgeLib.getGateways();
    }

    /// @inheritdoc IERC7786OpenBridge
    function getThreshold() external view virtual returns (uint8) {
        return ERC7786OpenBridgeLib.getThreshold();
    }

    /// @inheritdoc IERC7786OpenBridge
    function getRemoteBridge(bytes calldata chain) external view virtual returns (bytes memory) {
        return ERC7786OpenBridgeLib.getRemoteBridge(chain);
    }

    /// @inheritdoc IERC7786OpenBridge
    function addGateway(address gateway) external virtual {
        ERC7786OpenBridgeLib.addGateway(gateway);
    }

    /// @inheritdoc IERC7786OpenBridge
    function removeGateway(address gateway) external virtual {
        ERC7786OpenBridgeLib.removeGateway(gateway);
    }

    /// @inheritdoc IERC7786OpenBridge
    function setThreshold(uint8 threshold) external virtual {
        ERC7786OpenBridgeLib.setThreshold(threshold);
    }

    /// @inheritdoc IERC7786OpenBridge
    function registerRemoteBridge(bytes calldata bridge) external virtual {
        ERC7786OpenBridgeLib.registerRemoteBridge(bridge);
    }
}
