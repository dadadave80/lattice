// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IMulticall
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Multicall.sol)
/// @notice Interface for the Multicall module, enabling batched calls in a single transaction.
interface IMulticall {
    /// @notice Batch multiple calls to this contract in a single transaction.
    /// @dev Each call is executed via `delegatecall` so it runs in the context of the calling contract.
    /// If any call reverts, the entire batch reverts with the same revert data.
    /// @param data An array of calldata payloads to execute.
    /// @return results An array of return data from each call, in the same order as `data`.
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
}
