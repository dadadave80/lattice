// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title Recording1155Receiver
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only ERC-1155 receiver that accepts both hooks and records which one the token called last, the
///         operator, the batch length it saw and the `data` it was forwarded. Pins the receiver-hook choice (#237):
///         a one-element batch must still call `onERC1155BatchReceived`.
contract Recording1155Receiver {
    enum Hook {
        None,
        Single,
        Batch
    }

    Hook public lastHook;
    address public lastOperator;
    uint256 public batchIdsLength;
    bytes public lastData;

    function onERC1155Received(address operator, address, uint256, uint256, bytes calldata data)
        external
        returns (bytes4)
    {
        lastHook = Hook.Single;
        lastOperator = operator;
        lastData = data;
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address,
        uint256[] calldata ids,
        uint256[] calldata,
        bytes calldata data
    ) external returns (bytes4) {
        lastHook = Hook.Batch;
        lastOperator = operator;
        batchIdsLength = ids.length;
        lastData = data;
        return this.onERC1155BatchReceived.selector;
    }
}
