// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AxelarGatewayAdapterLib} from "@lattice/crosschain/libraries/AxelarGatewayAdapterLib.sol";
import {IAxelarGatewayAdapter} from "@lattice/interfaces/crosschain/IAxelarGatewayAdapter.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/IERC7786.sol";

/// @title AxelarGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin community-contracts `AxelarGatewayAdapter` (https://github.com/OpenZeppelin/openzeppelin-community-contracts, commit f7e5f08)
///         (https://github.com/OpenZeppelin/openzeppelin-community-contracts/blob/f7e5f08e8fd42023084eb41f4a992d7be897b915/contracts/crosschain/axelar/AxelarGatewayAdapter.sol)
/// @notice Dual-mode ERC-7786 gateway facet over Axelar GMP: `sendMessage` (source) emits an Axelar
///         `callContract`; `execute` (destination, called by the Axelar relayer) validates the approved
///         call + the trusted source gateway, then delivers to the ERC-7786 recipient. EVM chains only.
/// @dev Stateless delegator — logic/storage live in {AxelarGatewayAdapterLib}. OZ's `immutable` Axelar
///      gateway + `Ownable` are converted to ERC-7201 storage + AccessControl for the Diamond.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin
contract AxelarGatewayAdapter is IERC7786GatewaySource, IAxelarGatewayAdapter {
    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        external
        payable
        virtual
        returns (bytes32)
    {
        return AxelarGatewayAdapterLib.sendMessage(recipient, payload, attributes);
    }

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 selector) external pure virtual returns (bool) {
        return AxelarGatewayAdapterLib.supportsAttribute(selector);
    }

    /// @inheritdoc IAxelarGatewayAdapter
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external virtual {
        AxelarGatewayAdapterLib.execute(commandId, sourceChain, sourceAddress, payload);
    }

    /// @inheritdoc IAxelarGatewayAdapter
    function gateway() external view virtual returns (address) {
        return AxelarGatewayAdapterLib.gateway();
    }

    /// @inheritdoc IAxelarGatewayAdapter
    function getAxelarChain(bytes calldata chain) external view virtual returns (string memory) {
        return AxelarGatewayAdapterLib.getAxelarChain(chain);
    }

    /// @inheritdoc IAxelarGatewayAdapter
    function getErc7930Chain(string calldata axelar) external view virtual returns (bytes memory) {
        return AxelarGatewayAdapterLib.getErc7930Chain(axelar);
    }

    /// @inheritdoc IAxelarGatewayAdapter
    function getRemoteGateway(bytes calldata chain) external view virtual returns (bytes memory) {
        return AxelarGatewayAdapterLib.getRemoteGateway(chain);
    }

    /// @inheritdoc IAxelarGatewayAdapter
    function registerChainEquivalence(bytes calldata chain, string calldata axelar) external virtual {
        AxelarGatewayAdapterLib.registerChainEquivalence(chain, axelar);
    }

    /// @inheritdoc IAxelarGatewayAdapter
    function registerRemoteGateway(bytes calldata remote) external virtual {
        AxelarGatewayAdapterLib.registerRemoteGateway(remote);
    }
}
