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
    function minDirectCoverage() external view virtual returns (uint8) {
        return ERC7786OpenBridgeLib.minDirectCoverage();
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

    /// @inheritdoc IERC7786OpenBridge
    function setMinDirectCoverage(uint8 minDirectCoverage_) external virtual {
        ERC7786OpenBridgeLib.setMinDirectCoverage(minDirectCoverage_);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC7786OpenBridge methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `addGateway(address)` 0x68bb3795
    ///      `getGateways()` 0xd82778ce
    ///      `getRemoteBridge(bytes)` 0xd0673410
    ///      `getThreshold()` 0xe75235b8
    ///      `minDirectCoverage()` 0xc62c2f15
    ///      `receiveMessage(bytes32,bytes,bytes)` 0x2432ef26
    ///      `registerRemoteBridge(bytes)` 0x7e1c8ae5
    ///      `removeGateway(address)` 0x8a885e35
    ///      `sendMessage(bytes,bytes,bytes[])` 0xcdfe7f5c
    ///      `setMinDirectCoverage(uint8)` 0x10360b6b
    ///      `setThreshold(uint8)` 0xe5a98603
    ///      `supportsAttribute(bytes4)` 0xdc680a0f
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors =
        hex"68bb3795d82778ced0673410e75235b8c62c2f152432ef267e1c8ae58a885e35cdfe7f5c10360b6be5a98603dc680a0f";
    }
}
