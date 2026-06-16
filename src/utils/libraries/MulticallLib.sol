// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title Multicall Library
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Multicall.sol)
/// @notice Utility library for batching multiple calls to the same contract in one transaction.
/// @dev Stateless utility library (no ERC-7201 storage slot, no initializer). Each call is executed
/// as a `delegatecall` from the calling contract's context, so it runs with the same storage, value,
/// and `msg.sender` as the outer call, and is routed through the Diamond's fallback dispatcher
/// (enabling cross-facet batching). Because every sub-call is a delegatecall, all batched calls are
/// attributed to the outer `msg.sender`.
library MulticallLib {
    /// @notice Executes a batch of calls on the calling contract via `delegatecall`.
    /// @dev If any individual call reverts, the whole batch reverts with the same revert data.
    /// @param data An array of ABI-encoded calldata payloads to execute.
    /// @return results An array of raw return bytes from each call, in the same order as `data`.
    function multicall(bytes[] calldata data) internal returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i; i < data.length; ++i) {
            (bool ok, bytes memory ret) = address(this).delegatecall(data[i]);
            if (!ok) {
                assembly {
                    let len := mload(ret)
                    revert(add(0x20, ret), len)
                }
            }
            results[i] = ret;
        }
    }
}
